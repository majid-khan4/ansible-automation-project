output "vpc_id" {
	value = aws_vpc.main.id
}

output "public_subnet_ids" {
	value = aws_subnet.public[*].id 
}

output "private_subnet_ids" {
	value = aws_subnet.private[*].id
}

output "public_route_table_id" {
	value = aws_route_table.public.id
}

output "private_route_table_id" {
	value = aws_route_table.private.id
}

output "internet_gateway_id" {
	value = aws_internet_gateway.igw.id
}

output "nat_gateway_id" {
	value = aws_nat_gateway.nat.id
}

output "nat_eip_id" {
	value = aws_eip.nat.id
}

output "key_pair_name" {
	value = aws_key_pair.public_key.key_name
}

output "private_key_path" {
	value = local_file.private_key.filename
}

