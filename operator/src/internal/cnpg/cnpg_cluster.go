// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

package cnpg

import (
	"cmp"
	"fmt"
	"os"
	"strings"

	cnpgv1 "github.com/cloudnative-pg/cloudnative-pg/api/v1"
	"github.com/go-logr/logr"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/utils/pointer"

	dbpreview "github.com/documentdb/documentdb-operator/api/preview"
	otelcfg "github.com/documentdb/documentdb-operator/internal/otel"
	util "github.com/documentdb/documentdb-operator/internal/utils"
	ctrl "sigs.k8s.io/controller-runtime"
)

// isCombinedImageMode returns true when the DocumentDB CR opts into the
// combined-image path (single OCI image carrying both postgres binaries and
// extensions, no separate ImageVolume mount). Triggered by leaving
// spec.advanced.documentDBImage unset/empty. A nil advanced stanza also
// counts as "unset", which preserves the pre-refactor default behaviour.
func isCombinedImageMode(documentdb *dbpreview.DocumentDB) bool {
	if documentdb.Spec.Advanced == nil {
		return true
	}
	return strings.TrimSpace(documentdb.Spec.Advanced.DocumentDBImage) == ""
}

func GetCnpgClusterSpec(req ctrl.Request, documentdb *dbpreview.DocumentDB, documentdbImage, serviceAccountName, storageClass string, isPrimaryRegion bool, log logr.Logger) *cnpgv1.Cluster {
	adv := documentdb.Spec.Advanced
	var postgres *dbpreview.PostgresSpec
	if adv != nil {
		postgres = adv.Postgres
	}

	sidecarPluginName := ""
	if adv != nil {
		sidecarPluginName = adv.SidecarInjectorPluginName
	}
	if sidecarPluginName == "" {
		sidecarPluginName = util.DEFAULT_SIDECAR_INJECTOR_PLUGIN
	}

	// Get the gateway image for this DocumentDB instance
	gatewayImage := util.GetGatewayImageForDocumentDB(documentdb)
	specGatewayImage := ""
	if adv != nil {
		specGatewayImage = adv.GatewayImage
	}
	log.Info("Creating CNPG cluster with gateway image", "gatewayImage", gatewayImage, "documentdbName", documentdb.Name, "specGatewayImage", specGatewayImage)

	credentialSecretName := documentdb.Spec.DocumentDbCredentialSecret
	if credentialSecretName == "" {
		credentialSecretName = util.DEFAULT_DOCUMENTDB_CREDENTIALS_SECRET
	}

	// Configure storage class - use specified storage class or nil for default
	var storageClassPointer *string
	if storageClass != "" {
		storageClassPointer = &storageClass
	}

	combinedImage := isCombinedImageMode(documentdb)
	if combinedImage {
		log.Info("Combined-image mode enabled (spec.advanced.documentDBImage empty); skipping ImageVolume extensions plumbing", "documentdbName", documentdb.Name)
	}

	// Set ImageVolumeSource.PullPolicy for the extension image when configured.
	// This addresses the fact that ImageVolume sources DO support pull policies
	// (via corev1.ImageVolumeSource.PullPolicy), unlike regular container images
	// which only support pull policies on container specs.
	extensionImageSource := corev1.ImageVolumeSource{Reference: documentdbImage}
	if pullPolicy := parsePullPolicy(os.Getenv(util.DOCUMENTDB_IMAGE_PULL_POLICY_ENV)); pullPolicy != "" {
		extensionImageSource.PullPolicy = pullPolicy
	}

	return &cnpgv1.Cluster{
		ObjectMeta: metav1.ObjectMeta{
			Name:      req.Name,
			Namespace: req.Namespace,
			OwnerReferences: []metav1.OwnerReference{
				{
					APIVersion:         documentdb.APIVersion,
					Kind:               documentdb.Kind,
					Name:               documentdb.Name,
					UID:                documentdb.UID,
					Controller:         &[]bool{true}[0], // This cluster is controlled by the DocumentDB instance
					BlockOwnerDeletion: &[]bool{true}[0], // Block DocumentDB deletion until cluster is deleted
				},
			},
		},
		Spec: func() cnpgv1.ClusterSpec {
			spec := cnpgv1.ClusterSpec{
				Instances: documentdb.Spec.InstancesPerNode,
				ImageName: func() string {
					if adv != nil {
						return adv.PostgresImage
					}
					return ""
				}(),
				PrimaryUpdateMethod: cnpgv1.PrimaryUpdateMethodSwitchover,
				StorageConfiguration: cnpgv1.StorageConfiguration{
					StorageClass: storageClassPointer, // Use configured storage class or default
					Size:         documentdb.Spec.Resource.Storage.PvcSize,
				},
				InheritedMetadata: getInheritedMetadataLabels(documentdb.Name),
				Plugins: func() []cnpgv1.PluginConfiguration {
					params := map[string]string{
						"gatewayImage":               gatewayImage,
						"documentDbCredentialSecret": credentialSecretName,
					}
					if pullPolicy := os.Getenv(util.GATEWAY_IMAGE_PULL_POLICY_ENV); pullPolicy != "" {
						params["gatewayImagePullPolicy"] = pullPolicy
					}
					// If TLS is ready, surface secret name to plugin so it can mount certs.
					if documentdb.Status.TLS != nil && documentdb.Status.TLS.Ready && documentdb.Status.TLS.SecretName != "" {
						params["gatewayTLSSecret"] = documentdb.Status.TLS.SecretName
					}
					// Pass monitoring parameters to plugin for OTel sidecar injection.
					// Sidecar is only injected when monitoring is enabled.
					// Config hash triggers operator-initiated rolling restart on config changes.
					if documentdb.Spec.Monitoring != nil && documentdb.Spec.Monitoring.Enabled {
						params["otelCollectorImage"] = util.DEFAULT_OTEL_COLLECTOR_IMAGE
						params["otelConfigMapName"] = otelcfg.ConfigMapName(documentdb.Name)
						if promPort := otelcfg.ResolvePrometheusPort(documentdb.Spec.Monitoring); promPort > 0 {
							params["prometheusPort"] = fmt.Sprintf("%d", promPort)
						}
						// Compute config hash for change detection. The operator triggers a
						// rolling restart (via restart annotation) when plugin parameters
						// change, ensuring pods pick up new config.
						if configData, err := otelcfg.GenerateConfigMapData(documentdb.Name, req.Namespace, documentdb.Spec.Monitoring); err == nil {
							params["otelConfigHash"] = otelcfg.HashConfigMapData(configData)
						} else {
							log.Error(err, "Failed to generate OTel config hash; config changes may not trigger rolling restart")
						}
					}
					return []cnpgv1.PluginConfiguration{{
						Name:       sidecarPluginName,
						Enabled:    pointer.Bool(true),
						Parameters: params,
					}}
				}(),
				PostgresConfiguration: buildPostgresConfiguration(documentdb, extensionImageSource, combinedImage),
				Bootstrap:             getBootstrapConfiguration(documentdb, isPrimaryRegion, log),
				LogLevel:              cmp.Or(documentdb.Spec.LogLevel, "info"),
				Backup: &cnpgv1.BackupConfiguration{
					VolumeSnapshot: &cnpgv1.VolumeSnapshotConfiguration{
						SnapshotOwnerReference: "backup", // Set owner reference to 'backup' so that snapshots are deleted when Backup resource is deleted
					},
					Target: cnpgv1.BackupTarget("primary"),
				},
				Affinity: func() cnpgv1.AffinityConfiguration {
					if adv != nil && adv.Affinity != nil {
						return *adv.Affinity
					}
					return cnpgv1.AffinityConfiguration{}
				}(),
			}
			spec.MaxStopDelay = getMaxStopDelayOrDefault(documentdb)

			// Combined-image mode: honour optional UID/GID overrides for the
			// in-image postgres user (e.g., a custom image runs as uid 1000).
			// Pointer types let us distinguish "unset" from "explicitly 0".
			if postgres != nil {
				if postgres.UID != nil {
					spec.PostgresUID = int64(*postgres.UID)
				}
				if postgres.GID != nil {
					spec.PostgresGID = int64(*postgres.GID)
				}
			}

			// Plumb image pull secrets through to CNPG so they apply to the
			// PG container, the gateway sidecar (which lives in the same pod),
			// and any other container CNPG schedules into the cluster's pods.
			// CNPG's LocalObjectReference is a structural alias of
			// corev1.LocalObjectReference (single .Name field), so we translate
			// element-by-element rather than coercing types.
			if adv != nil && len(adv.ImagePullSecrets) > 0 {
				spec.ImagePullSecrets = make([]cnpgv1.LocalObjectReference, 0, len(adv.ImagePullSecrets))
				for _, ref := range adv.ImagePullSecrets {
					spec.ImagePullSecrets = append(spec.ImagePullSecrets, cnpgv1.LocalObjectReference{Name: ref.Name})
				}
			}

			return spec
		}(),
	}
}

// buildPostgresConfiguration assembles the PostgresConfiguration block for the
// CNPG cluster. In the default (ImageVolume) mode, the documentdb extension is
// mounted via ImageVolumeSource and the operator injects DocumentDB-specific
// shared_preload_libraries and GUC parameters. In combined-image mode the
// extensions are pre-baked into spec.postgresImage, so we leave the Extensions
// list empty and defer shared_preload_libraries / GUC tuning to the image's
// own postgres configuration unless the caller explicitly opts in via
// spec.preloadLibraries.
func buildPostgresConfiguration(documentdb *dbpreview.DocumentDB, extensionImageSource corev1.ImageVolumeSource, combinedImage bool) cnpgv1.PostgresConfiguration {
	// PgHBA is unrelated to the extension layout and stays the same in both modes.
	pgHBA := []string{
		"host all all 0.0.0.0/0 trust",
		"host all all ::0/0 trust",
		"host replication all all trust",
	}

	var preloadLibraries []string
	if documentdb.Spec.Advanced != nil && documentdb.Spec.Advanced.Postgres != nil {
		preloadLibraries = documentdb.Spec.Advanced.Postgres.PreloadLibraries
	}

	if combinedImage {
		// Combined-image mode: skip the ImageVolume extension mount and the
		// documentdb-extension-specific GUC parameters. Honour an explicit
		// preloadLibraries override if provided; otherwise leave nil so the
		// image's own shared_preload_libraries setting is authoritative.
		return cnpgv1.PostgresConfiguration{
			AdditionalLibraries: preloadLibraries,
			PgHBA:               pgHBA,
		}
	}

	// Default (ImageVolume) mode: preserve byte-identical output to the
	// pre-combined-image-mode behaviour.
	additionalLibraries := preloadLibraries
	if additionalLibraries == nil {
		additionalLibraries = []string{"pg_cron", "pg_documentdb_core", "pg_documentdb"}
	}

	return cnpgv1.PostgresConfiguration{
		Extensions: []cnpgv1.ExtensionConfiguration{
			{
				Name:                 "documentdb",
				ImageVolumeSource:    extensionImageSource,
				DynamicLibraryPath:   []string{"lib"},
				ExtensionControlPath: []string{"share"},
				LdLibraryPath:        []string{"lib", "system"},
			},
		},
		AdditionalLibraries: additionalLibraries,
		Parameters: func() map[string]string {
			params := map[string]string{
				"cron.database_name":    "postgres",
				"max_replication_slots": "10",
				"max_wal_senders":       "10",
			}
			// TODO: once DocumentDB supports change streams natively, additional GUC parameters may be needed here.
			if dbpreview.IsFeatureGateEnabled(documentdb, dbpreview.FeatureGateChangeStreams) {
				params["wal_level"] = "logical"
			}
			return params
		}(),
		PgHBA: pgHBA,
	}
}

func getInheritedMetadataLabels(appName string) *cnpgv1.EmbeddedObjectMetadata {
	return &cnpgv1.EmbeddedObjectMetadata{
		Labels: map[string]string{
			util.LABEL_APP:          appName,
			util.LABEL_REPLICA_TYPE: "primary", // TODO: Replace with CNPG default setup
		},
	}
}

func getBootstrapConfiguration(documentdb *dbpreview.DocumentDB, isPrimaryRegion bool, log logr.Logger) *cnpgv1.BootstrapConfiguration {
	if isPrimaryRegion && documentdb.Spec.Bootstrap != nil && documentdb.Spec.Bootstrap.Recovery != nil {
		recovery := documentdb.Spec.Bootstrap.Recovery

		// Handle backup recovery
		if recovery.Backup.Name != "" {
			backupName := recovery.Backup.Name
			log.Info("DocumentDB cluster will be bootstrapped from backup", "backupName", backupName)
			return &cnpgv1.BootstrapConfiguration{
				Recovery: &cnpgv1.BootstrapRecovery{
					Backup: &cnpgv1.BackupSource{
						LocalObjectReference: recovery.Backup,
					},
				},
			}
		}

		// Handle PV recovery (via temporary PVC created by the controller)
		if recovery.PersistentVolume != nil && recovery.PersistentVolume.Name != "" {
			tempPVCName := util.TempPVCNameForPVRecovery(documentdb.Name)
			log.Info("DocumentDB cluster will be bootstrapped from PV via temp PVC",
				"pvName", recovery.PersistentVolume.Name, "tempPVC", tempPVCName)
			return &cnpgv1.BootstrapConfiguration{
				Recovery: &cnpgv1.BootstrapRecovery{
					VolumeSnapshots: &cnpgv1.DataSource{
						Storage: corev1.TypedLocalObjectReference{
							Name:     tempPVCName,
							Kind:     "PersistentVolumeClaim",
							APIGroup: pointer.String(""),
						},
					},
				},
			}
		}
	}

	return getDefaultBootstrapConfiguration(documentdb)
}

func getDefaultBootstrapConfiguration(documentdb *dbpreview.DocumentDB) *cnpgv1.BootstrapConfiguration {
	// Honour an explicit PostInitSQL override (typically set in combined-image
	// mode where the baked-in extension set differs from documentdb's default).
	postInitSQL := []string{
		"CREATE EXTENSION documentdb CASCADE",
		"CREATE ROLE documentdb WITH LOGIN PASSWORD 'Admin100'",
		"ALTER ROLE documentdb WITH SUPERUSER CREATEDB CREATEROLE REPLICATION BYPASSRLS",
	}
	if documentdb != nil && documentdb.Spec.Advanced != nil && documentdb.Spec.Advanced.Postgres != nil && len(documentdb.Spec.Advanced.Postgres.PostInitSQL) > 0 {
		postInitSQL = documentdb.Spec.Advanced.Postgres.PostInitSQL
	}

	return &cnpgv1.BootstrapConfiguration{
		InitDB: &cnpgv1.BootstrapInitDB{
			PostInitSQL: postInitSQL,
		},
	}
}

// getMaxStopDelayOrDefault returns StopDelay if set, otherwise util.CNPG_DEFAULT_STOP_DELAY
func getMaxStopDelayOrDefault(documentdb *dbpreview.DocumentDB) int32 {
	if documentdb.Spec.Advanced != nil && documentdb.Spec.Advanced.Timeouts != nil && documentdb.Spec.Advanced.Timeouts.StopDelay != 0 {
		return documentdb.Spec.Advanced.Timeouts.StopDelay
	}
	return util.CNPG_DEFAULT_STOP_DELAY
}

// parsePullPolicy converts a string to a corev1.PullPolicy.
// Returns empty string for unrecognized values.
func parsePullPolicy(value string) corev1.PullPolicy {
	switch corev1.PullPolicy(value) {
	case corev1.PullAlways, corev1.PullNever, corev1.PullIfNotPresent:
		return corev1.PullPolicy(value)
	default:
		return ""
	}
}
