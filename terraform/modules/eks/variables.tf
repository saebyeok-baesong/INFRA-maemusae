variable "name" {
  description = "클러스터 이름이자 IAM 역할, 시작 템플릿 이름 접두사"
  type        = string
}

variable "kubernetes_version" {
  description = "EKS 버전"
  type        = string
}

variable "private_subnet_ids_by_az" {
  description = "AZ => 프라이빗 서브넷 ID. 컨트롤 플레인이 쓴다"
  type        = map(string)
}

variable "node_subnet_ids_by_az" {
  description = "AZ => 노드그룹 서브넷 ID. 노드가 부팅하며 이미지를 받으려면 NAT 경로가 있어야 해서, 호출하는 쪽이 경로가 생긴 뒤의 값으로 넘긴다"
  type        = map(string)
}

variable "node_security_group_id" {
  description = "10-base 가 만든 노드 보안 그룹. RDS 가 이 그룹에서 오는 5432 만 받는다"
  type        = string
}

variable "endpoint_public_access_cidrs" {
  description = "공개 API 엔드포인트에 허용할 CIDR"
  type        = list(string)
}

variable "admin_principal_arns" {
  description = "클러스터 관리자 Access Entry 를 줄 IAM 주체. 클러스터를 만드는 주체는 빼고 넘긴다 (EKS 가 자동으로 만든다)"
  type        = list(string)
}

variable "node_groups" {
  description = "노드그룹 이름 => AZ, 인스턴스, 대수. 이름이 노드 라벨과 taint role=<이름> 이 된다"
  type = map(object({
    az            = string
    instance_type = string
    size          = number
  }))
}

variable "tags" {
  description = "노드 EC2, 루트 볼륨, PVC 볼륨에 붙일 태그. 공급자 default_tags 가 닿지 않는 곳이다"
  type        = map(string)
}
