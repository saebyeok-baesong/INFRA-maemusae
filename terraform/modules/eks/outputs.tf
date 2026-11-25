output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  value = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "EKS 가 만든 클러스터 보안 그룹. LB Controller 가 NLB 규칙을 이 그룹에 넣는다"
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "node_groups" {
  description = "노드그룹 이름 => 서브넷, 라벨, taint"
  value = {
    for k, ng in aws_eks_node_group.this : k => {
      subnet_ids = ng.subnet_ids
      labels     = ng.labels
      taints     = [for t in ng.taint : "${t.key}=${t.value}:${t.effect}"]
    }
  }
}

output "addons" {
  value = sort(concat(keys(aws_eks_addon.before_nodes), keys(aws_eks_addon.after_nodes)))
}
