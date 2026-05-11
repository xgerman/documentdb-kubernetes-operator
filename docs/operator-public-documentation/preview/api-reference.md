# API Reference

## Packages
- [documentdb.io/preview](#documentdbiopreview)


## documentdb.io/preview

Package preview contains API Schema definitions for the db preview API group.

### Resource Types
- [Backup](#backup)
- [DocumentDB](#documentdb)
- [ScheduledBackup](#scheduledbackup)



#### AdvancedSpec



AdvancedSpec groups expert-mode configuration. All fields are optional and
the operator applies safe defaults when this stanza is absent.



_Appears in:_
- [DocumentDBSpec](#documentdbspec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `documentDBImage` _string_ | DocumentDBImage is the container image to use for the DocumentDB<br />extension. Changing this is not recommended for most users.<br />Leaving this empty enables "combined-image mode": the operator skips<br />mounting the extension via ImageVolume and assumes the chosen<br />postgresImage already carries the extension and is configured to load<br />it via shared_preload_libraries. Most users should leave this empty<br />and rely on the operator's default extension image. |  | Optional: \{\} <br /> |
| `gatewayImage` _string_ | GatewayImage is the container image to use for the DocumentDB Gateway<br />sidecar. Changing this is not recommended for most users.<br />If not specified, defaults to a version that matches the DocumentDB<br />operator version. |  | Optional: \{\} <br /> |
| `postgresImage` _string_ | PostgresImage is the container image to use for the PostgreSQL server.<br />If not specified, defaults to the last stable PostgreSQL version<br />compatible with DocumentDB. Must use trixie (Debian 13) base to match<br />the extension's GLIBC requirements. | ghcr.io/cloudnative-pg/postgresql:18-minimal-trixie | Optional: \{\} <br /> |
| `imagePullSecrets` _[LocalObjectReference](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.35/#localobjectreference-v1-core) array_ | ImagePullSecrets is the list of references to secrets in the same<br />namespace to use for pulling any of the images used by the DocumentDB<br />cluster (postgresImage, gatewayImage, sidecar). Only the .name field<br />is honoured, matching the standard Kubernetes<br />corev1.LocalObjectReference contract. Equivalent to<br />PodSpec.ImagePullSecrets — used when the configured images live in a<br />private registry such as a token-protected ACR. |  | Optional: \{\} <br /> |
| `sidecarInjectorPluginName` _string_ | SidecarInjectorPluginName is the name of the sidecar injector plugin<br />to use. Immutable after cluster creation. |  | Optional: \{\} <br /> |
| `walReplicaPluginName` _string_ | WalReplicaPluginName is the name of the wal replica plugin to use. |  | Optional: \{\} <br /> |
| `affinity` _[AffinityConfiguration](https://pkg.go.dev/github.com/cloudnative-pg/cloudnative-pg/api/v1#AffinityConfiguration)_ | Affinity/Anti-affinity rules for Pods (cnpg passthrough). |  | Optional: \{\} <br /> |
| `timeouts` _[Timeouts](#timeouts)_ | Timeouts groups operational tuning knobs for cluster lifecycle. |  | Optional: \{\} <br /> |
| `postgres` _[PostgresSpec](#postgresspec)_ | Postgres groups runtime-configuration knobs for the postgres process<br />inside the postgresImage container. Useful primarily for<br />combined-image deployments that ship custom extensions or a non-default<br />postgres user. |  | Optional: \{\} <br /> |


#### Backup









| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `apiVersion` _string_ | `documentdb.io/preview` | | |
| `kind` _string_ | `Backup` | | |
| `metadata` _[ObjectMeta](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.35/#objectmeta-v1-meta)_ | Refer to Kubernetes API documentation for fields of `metadata`. |  |  |
| `spec` _[BackupSpec](#backupspec)_ |  |  |  |


#### BackupConfiguration



BackupConfiguration defines backup settings for DocumentDB.



_Appears in:_
- [DocumentDBSpec](#documentdbspec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `retentionDays` _integer_ | RetentionDays specifies how many days backups should be retained.<br />If not specified, the default retention period is 30 days. | 30 | Maximum: 365 <br />Minimum: 1 <br />Optional: \{\} <br /> |


#### BackupSpec



BackupSpec defines the desired state of Backup.



_Appears in:_
- [Backup](#backup)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `cluster` _[LocalObjectReference](https://pkg.go.dev/github.com/cloudnative-pg/cloudnative-pg/api/v1#LocalObjectReference)_ | Cluster specifies the DocumentDB cluster to backup.<br />The cluster must exist in the same namespace as the Backup resource. |  | Required: \{\} <br /> |
| `retentionDays` _integer_ | RetentionDays specifies how many days the backup should be retained.<br />If not specified, the default retention period from the cluster's backup retention policy will be used. |  | Optional: \{\} <br /> |


#### BootstrapConfiguration



BootstrapConfiguration defines how to bootstrap a DocumentDB cluster.



_Appears in:_
- [DocumentDBSpec](#documentdbspec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `recovery` _[RecoveryConfiguration](#recoveryconfiguration)_ | Recovery configures recovery from a backup. |  | Optional: \{\} <br /> |


#### CertManagerTLS



CertManagerTLS holds parameters for cert-manager driven certificates.



_Appears in:_
- [GatewayTLS](#gatewaytls)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `issuerRef` _[IssuerRef](#issuerref)_ |  |  |  |
| `dnsNames` _string array_ | DNSNames for the certificate SANs. If empty, operator will add Service DNS names. |  |  |
| `secretName` _string_ | SecretName optional explicit name for the target secret. If empty a default is chosen. |  |  |


#### ClusterReplication







_Appears in:_
- [DocumentDBSpec](#documentdbspec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `crossCloudNetworkingStrategy` _string_ | CrossCloudNetworking determines which type of networking mechanics for the replication |  | Enum: [AzureFleet Istio None] <br /> |
| `primary` _string_ | Primary is the name of the primary cluster for replication. |  |  |
| `clusterList` _[MemberCluster](#membercluster) array_ | ClusterList is the list of clusters participating in replication. |  |  |
| `highAvailability` _boolean_ | Whether or not to have replicas on the primary cluster. |  |  |


#### DocumentDB



DocumentDB is the Schema for the dbs API.





| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `apiVersion` _string_ | `documentdb.io/preview` | | |
| `kind` _string_ | `DocumentDB` | | |
| `metadata` _[ObjectMeta](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.35/#objectmeta-v1-meta)_ | Refer to Kubernetes API documentation for fields of `metadata`. |  |  |
| `spec` _[DocumentDBSpec](#documentdbspec)_ |  |  |  |


#### DocumentDBSpec



DocumentDBSpec defines the desired state of DocumentDB.



_Appears in:_
- [DocumentDB](#documentdb)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `nodeCount` _integer_ | NodeCount is the number of nodes in the DocumentDB cluster. Must be 1. |  | Maximum: 1 <br />Minimum: 1 <br /> |
| `instancesPerNode` _integer_ | InstancesPerNode is the number of DocumentDB instances per node. Range: 1-3. |  | Maximum: 3 <br />Minimum: 1 <br /> |
| `resource` _[Resource](#resource)_ | Resource specifies the storage resources for DocumentDB. |  |  |
| `documentDBVersion` _string_ | DocumentDBVersion specifies the version for all DocumentDB components (engine, gateway).<br />When set, this overrides the default versions for documentDBImage and gatewayImage.<br />Individual image fields take precedence over this version. |  |  |
| `documentDbCredentialSecret` _string_ | DocumentDbCredentialSecret is the name of the Kubernetes Secret containing credentials<br />for the DocumentDB gateway (expects keys `username` and `password`). If omitted,<br />a default secret name `documentdb-credentials` is used.<br />NOTE: Immutable today; will be relaxed in a future release to support credential rotation. |  |  |
| `clusterReplication` _[ClusterReplication](#clusterreplication)_ | ClusterReplication configures cross-cluster replication for DocumentDB. |  |  |
| `exposeViaService` _[ExposeViaService](#exposeviaservice)_ | ExposeViaService configures how to expose DocumentDB via a Kubernetes service.<br />This can be a LoadBalancer or ClusterIP service. |  |  |
| `environment` _string_ | Environment specifies the cloud environment for deployment<br />This determines cloud-specific service annotations for LoadBalancer services |  | Enum: [eks aks gke] <br /> |
| `tls` _[TLSConfiguration](#tlsconfiguration)_ | TLS configures certificate management for DocumentDB components. |  |  |
| `logLevel` _string_ | Overrides default log level for the DocumentDB cluster. |  |  |
| `bootstrap` _[BootstrapConfiguration](#bootstrapconfiguration)_ | Bootstrap configures the initialization of the DocumentDB cluster. |  | Optional: \{\} <br /> |
| `backup` _[BackupConfiguration](#backupconfiguration)_ | Backup configures backup settings for DocumentDB. |  | Optional: \{\} <br /> |
| `featureGates` _object (keys:string, values:boolean)_ | FeatureGates enables or disables optional DocumentDB features.<br />Keys are PascalCase feature names following the Kubernetes feature gate convention.<br />Example: \{"ChangeStreams": true\}<br />IMPORTANT: When adding a new feature gate, update ALL of the following:<br />1. Add a new FeatureGate* constant in documentdb_types.go<br />2. Add the key name to the XValidation CEL rule's allowed list below<br />3. Add a default entry in the featureGateDefaults map in documentdb_types.go |  | Optional: \{\} <br /> |
| `schemaVersion` _string_ | SchemaVersion controls the desired schema version for the DocumentDB extension.<br />The operator never changes your database schema unless you ask:<br />  - Set schemaVersion → updates the database schema (irreversible)<br />  - Set schemaVersion: "auto" → schema auto-updates with binary<br />Once the schema has been updated, the operator blocks image rollback below the<br />installed schema version to prevent running an untested binary/schema combination.<br />Values:<br />  - "" (empty, default): Two-phase mode. Image upgrades happen automatically,<br />    but ALTER EXTENSION UPDATE does NOT run. Users must explicitly set this<br />    field to finalize the schema upgrade. This is the safest option for production<br />    as it allows rollback by reverting the image before committing the schema change.<br />  - "auto": Schema automatically updates to match the binary version whenever<br />    the binary is upgraded. This is the simplest mode but provides no rollback<br />    safety window. Only recommended for single-region clusters.<br />  - "<version>" (e.g. "0.112.0"): Schema updates to exactly this version.<br />    Must be <= the binary version. |  | Pattern: `^(auto\|[0-9]+\.[0-9]+\.[0-9]+)?$` <br />Optional: \{\} <br /> |
| `monitoring` _[MonitoringSpec](#monitoringspec)_ | Monitoring configures observability via an OTel Collector sidecar. |  | Optional: \{\} <br /> |
| `advanced` _[AdvancedSpec](#advancedspec)_ | Advanced groups expert-mode and rarely-touched configuration. Leaving<br />it unset is the supported path for typical users — the operator applies<br />safe defaults for everything in this block.<br />Knobs that belong here change deployment internals (custom container<br />images, plugin names, pod scheduling, postgres process configuration)<br />rather than user-facing functionality. Setting any of these fields<br />implies you understand the trade-offs and have tested the resulting<br />configuration. |  | Optional: \{\} <br /> |


#### ExporterSpec



ExporterSpec configures metric export destinations.



_Appears in:_
- [MonitoringSpec](#monitoringspec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `otlp` _[OTLPExporterSpec](#otlpexporterspec)_ | OTLP configures the OpenTelemetry Protocol exporter. |  | Optional: \{\} <br /> |
| `prometheus` _[PrometheusExporterSpec](#prometheusexporterspec)_ | Prometheus configures a Prometheus scrape endpoint on the OTel Collector sidecar. |  | Optional: \{\} <br /> |


#### ExposeViaService







_Appears in:_
- [DocumentDBSpec](#documentdbspec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `serviceType` _string_ | ServiceType determines the type of service to expose for DocumentDB. |  | Enum: [LoadBalancer ClusterIP] <br /> |


#### GatewayTLS



GatewayTLS defines TLS configuration for the gateway sidecar (Phase 1: certificate provisioning only)



_Appears in:_
- [TLSConfiguration](#tlsconfiguration)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `mode` _string_ | Mode selects the TLS management strategy.<br />Defaults to SelfSigned if not specified. | SelfSigned | Enum: [SelfSigned CertManager Provided] <br /> |
| `certManager` _[CertManagerTLS](#certmanagertls)_ | CertManager config when Mode=CertManager. |  |  |
| `provided` _[ProvidedTLS](#providedtls)_ | Provided secret reference when Mode=Provided. |  |  |


#### GlobalEndpointsTLS



GlobalEndpointsTLS acts as a placeholder for future global endpoint TLS settings.



_Appears in:_
- [TLSConfiguration](#tlsconfiguration)



#### IssuerRef



IssuerRef references a cert-manager Issuer or ClusterIssuer.



_Appears in:_
- [CertManagerTLS](#certmanagertls)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `name` _string_ |  |  |  |
| `kind` _string_ | Kind of issuer (Issuer or ClusterIssuer). Defaults to Issuer. |  |  |
| `group` _string_ | Group defaults to cert-manager.io |  |  |


#### MemberCluster







_Appears in:_
- [ClusterReplication](#clusterreplication)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `name` _string_ | Name is the name of the member cluster. |  |  |
| `environment` _string_ | EnvironmentOverride is the cloud environment of the member cluster.<br />Will default to the global setting |  | Enum: [eks aks gke] <br /> |
| `storageClass` _string_ | StorageClassOverride specifies the storage class for DocumentDB persistent volumes in this member cluster. |  |  |


#### MonitoringSpec



MonitoringSpec configures observability via an OTel Collector sidecar.



_Appears in:_
- [DocumentDBSpec](#documentdbspec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `enabled` _boolean_ | Enabled turns on the OTel Collector sidecar for metrics collection. |  |  |
| `exporter` _[ExporterSpec](#exporterspec)_ | Exporter configures where metrics are sent. |  | Optional: \{\} <br /> |


#### OTLPExporterSpec



OTLPExporterSpec configures the OTLP exporter.



_Appears in:_
- [ExporterSpec](#exporterspec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `endpoint` _string_ | Endpoint is the OTLP gRPC endpoint (e.g., "otel-collector.monitoring:4317"). |  |  |


#### PVRecoveryConfiguration



PVRecoveryConfiguration defines settings for recovering from a retained PersistentVolume.



_Appears in:_
- [RecoveryConfiguration](#recoveryconfiguration)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `name` _string_ | Name is the name of the PersistentVolume to recover from.<br />The PV must exist and be in Available or Released state. |  | MinLength: 1 <br /> |


#### PostgresSpec



PostgresSpec groups runtime-configuration knobs for the postgres process.



_Appears in:_
- [AdvancedSpec](#advancedspec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `uid` _integer_ | UID is the UID under which CloudNative-PG launches PostgreSQL inside<br />the postgresImage container. Default behaviour (unset) uses the CNPG<br />default for the chosen image. Set this when using a combined image<br />whose postgres user has a non-default UID. Must be set together with<br />GID. |  | Optional: \{\} <br /> |
| `gid` _integer_ | GID is the GID under which CloudNative-PG launches PostgreSQL.<br />See UID. Must be set together with UID. |  | Optional: \{\} <br /> |
| `preloadLibraries` _string array_ | PreloadLibraries overrides the default shared_preload_libraries<br />injected by the operator. When set, replaces the default<br />["pg_cron", "pg_documentdb_core", "pg_documentdb"] list. Useful for<br />combined-image deployments where extensions are pre-baked and<br />shared_preload_libraries is configured by the image itself. |  | Optional: \{\} <br /> |
| `postInitSQL` _string array_ | PostInitSQL overrides the default post-init SQL block run by CNPG<br />(which by default does CREATE EXTENSION documentdb CASCADE plus role<br />setup). When set, replaces the default block entirely. Useful for<br />combined-image deployments that ship a different extension set. |  | Optional: \{\} <br /> |


#### PostgresTLS



PostgresTLS acts as a placeholder for future Postgres TLS settings.



_Appears in:_
- [TLSConfiguration](#tlsconfiguration)



#### PrometheusExporterSpec



PrometheusExporterSpec configures the Prometheus scrape endpoint exporter.



_Appears in:_
- [ExporterSpec](#exporterspec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `port` _integer_ | Port for the Prometheus scrape endpoint. Defaults to 8888. | 8888 | Maximum: 65535 <br />Minimum: 1024 <br />Optional: \{\} <br /> |


#### ProvidedTLS



ProvidedTLS references an existing secret that contains tls.crt/tls.key (and optional ca.crt).



_Appears in:_
- [GatewayTLS](#gatewaytls)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `secretName` _string_ |  |  |  |


#### RecoveryConfiguration



RecoveryConfiguration defines recovery settings for bootstrapping a DocumentDB cluster.



_Appears in:_
- [BootstrapConfiguration](#bootstrapconfiguration)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `backup` _[LocalObjectReference](https://pkg.go.dev/github.com/cloudnative-pg/cloudnative-pg/api/v1#LocalObjectReference)_ | Backup specifies the source backup to restore from. |  | Optional: \{\} <br /> |
| `persistentVolume` _[PVRecoveryConfiguration](#pvrecoveryconfiguration)_ | PersistentVolume specifies the PV to restore from.<br />The operator will create a temporary PVC bound to this PV, use it for CNPG recovery,<br />and delete the temporary PVC after the cluster is healthy.<br />Cannot be used together with Backup. |  | Optional: \{\} <br /> |


#### Resource







_Appears in:_
- [DocumentDBSpec](#documentdbspec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `storage` _[StorageConfiguration](#storageconfiguration)_ | Storage configuration for DocumentDB persistent volumes. |  |  |


#### ScheduledBackup









| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `apiVersion` _string_ | `documentdb.io/preview` | | |
| `kind` _string_ | `ScheduledBackup` | | |
| `metadata` _[ObjectMeta](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.35/#objectmeta-v1-meta)_ | Refer to Kubernetes API documentation for fields of `metadata`. |  |  |
| `spec` _[ScheduledBackupSpec](#scheduledbackupspec)_ |  |  |  |


#### ScheduledBackupSpec



ScheduledBackupSpec defines the desired state of ScheduledBackup



_Appears in:_
- [ScheduledBackup](#scheduledbackup)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `cluster` _[LocalObjectReference](https://pkg.go.dev/github.com/cloudnative-pg/cloudnative-pg/api/v1#LocalObjectReference)_ | Cluster specifies the DocumentDB cluster to backup.<br />The cluster must exist in the same namespace as the ScheduledBackup resource. |  | Required: \{\} <br /> |
| `schedule` _string_ | Schedule defines when backups should be created using cron expression format.<br />See https://pkg.go.dev/github.com/robfig/cron#hdr-CRON_Expression_Format |  | Required: \{\} <br /> |
| `retentionDays` _integer_ | RetentionDays specifies how many days the backups should be retained.<br />If not specified, the default retention period from the cluster's backup retention policy will be used. |  | Optional: \{\} <br /> |


#### StorageConfiguration







_Appears in:_
- [Resource](#resource)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `pvcSize` _string_ | PvcSize is the size of the persistent volume claim for DocumentDB storage (e.g., "10Gi"). |  | MinLength: 1 <br /> |
| `storageClass` _string_ | StorageClass specifies the storage class for DocumentDB persistent volumes.<br />If not specified, the cluster's default storage class will be used. |  |  |
| `persistentVolumeReclaimPolicy` _string_ | PersistentVolumeReclaimPolicy controls what happens to the PersistentVolume when<br />the DocumentDB cluster is deleted.<br />When a DocumentDB cluster is deleted, the following chain of deletions occurs:<br />DocumentDB deletion → CNPG Cluster deletion → PVC deletion → PV deletion (based on this policy)<br />Options:<br />  - Retain (default): The PV is preserved after cluster deletion, allowing manual<br />    data recovery or forensic analysis. Use for production workloads where data<br />    safety is critical. Orphaned PVs must be manually deleted when no longer needed.<br />  - Delete: The PV is automatically deleted when the PVC is deleted. Use for development,<br />    testing, or ephemeral environments where data persistence is not required.<br />WARNING: Setting this to "Delete" means all data will be permanently lost when<br />the DocumentDB cluster is deleted. This cannot be undone. | Retain | Enum: [Retain Delete] <br />Optional: \{\} <br /> |


#### TLSConfiguration



TLSConfiguration aggregates TLS settings across DocumentDB components.



_Appears in:_
- [DocumentDBSpec](#documentdbspec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `gateway` _[GatewayTLS](#gatewaytls)_ | Gateway configures TLS for the gateway sidecar (Phase 1: certificate provisioning only). |  |  |
| `postgres` _[PostgresTLS](#postgrestls)_ | Postgres configures TLS for the Postgres server (placeholder for future phases). |  |  |
| `globalEndpoints` _[GlobalEndpointsTLS](#globalendpointstls)_ | GlobalEndpoints configures TLS for global endpoints (placeholder for future phases). |  |  |


#### Timeouts







_Appears in:_
- [AdvancedSpec](#advancedspec)

| Field | Description | Default | Validation |
| --- | --- | --- | --- |
| `stopDelay` _integer_ |  |  | Maximum: 1800 <br />Minimum: 0 <br /> |


