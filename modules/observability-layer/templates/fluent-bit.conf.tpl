[SERVICE]
    Flush         5
    Log_Level     info
    Daemon        off
    Parsers_File  parsers.conf
    HTTP_Server   On
    HTTP_Listen   0.0.0.0
    HTTP_Port     2020
    Health_Check  On
    storage.path  /tmp/fluent-bit/storage
    storage.sync  normal
    storage.checksum off
    storage.max_chunks_up 128

[INPUT]
    Name              tail
    Path              /var/log/containers/*.log
    multiline.parser  docker, cri
    Tag               kube.*
    Refresh_Interval  5
    Mem_Buf_Limit     50MB
    Skip_Long_Lines   On
    Skip_Empty_Lines  On
    storage.type      filesystem
    DB                /tmp/fluent-bit/tail_db

[INPUT]
    Name            systemd
    Tag             host.*
    Systemd_Filter  _SYSTEMD_UNIT=kubelet.service
    Systemd_Filter  _SYSTEMD_UNIT=docker.service
    Systemd_Filter  _SYSTEMD_UNIT=containerd.service
    storage.type    filesystem

[FILTER]
    Name                kubernetes
    Match               kube.*
    Kube_URL            https://kubernetes.default.svc:443
    Kube_CA_File        /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
    Kube_Token_File     /var/run/secrets/kubernetes.io/serviceaccount/token
    Kube_Tag_Prefix     kube.var.log.containers.
    Merge_Log           On
    Keep_Log            Off
    K8S-Logging.Parser  On
    K8S-Logging.Exclude Off
    Annotations         Off
    Labels              On

[FILTER]
    Name    grep
    Match   kube.*
    Exclude log ^\s*$

[FILTER]
    Name          record_modifier
    Match         *
    Record        cluster_name ${cluster_name}
    Record        region ${region}

# Add tenant labeling based on namespace
%{ for tenant_name, tenant_config in tenant_configs ~}
[FILTER]
    Name          record_modifier
    Match         kube.var.log.containers.*_${tenant_config.namespace}_*
    Record        tenant ${tenant_name}
    Record        tenant_namespace ${tenant_config.namespace}

%{ endfor ~}

# Output to S3 with enhanced hierarchical partitioning
[OUTPUT]
    Name                         s3
    Match                        *
    bucket                       ${s3_bucket_name}
    region                       ${region}
    total_file_size             50M
    upload_timeout              10m
    use_put_object              On
    s3_key_format               logs/cluster=${cluster_name}/tenant=$${tenant}/service=$${kubernetes_pod_name}/year=%Y/month=%m/day=%d/hour=%H/fluent-bit-logs-%Y%m%d-%H%M%S-$UUID.gz
    s3_key_format_tag_delimiters .-
    auto_retry_requests         true
    storage_class               STANDARD_IA
    compression                 gzip
    content_type                application/gzip

# Fallback output for debugging
[OUTPUT]
    Name   stdout
    Match  *
    Format json_lines
