provider "aws" {
}

resource "random_id" "id" {
  byte_length = 8
}

resource "aws_iam_role" "appsync" {
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "appsync.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_dynamodb_table" "group" {
  name         = "group-${random_id.id.hex}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}
resource "aws_dynamodb_table" "user" {
  name         = "user-${random_id.id.hex}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "group_id"
    type = "S"
  }

  attribute {
    name = "last_active"
    type = "S"
  }

  attribute {
    name = "group_id#status"
    type = "S"
  }

  global_secondary_index {
    name            = "groupId"
    hash_key        = "group_id"
    range_key       = "last_active"
    projection_type = "ALL"
  }
  global_secondary_index {
    name            = "groupIdStatus"
    hash_key        = "group_id#status"
    range_key       = "last_active"
    projection_type = "ALL"
  }
}

# sample data

resource "aws_dynamodb_table_item" "group1" {
  table_name = aws_dynamodb_table.group.name
  hash_key   = aws_dynamodb_table.group.hash_key

  item = <<ITEM
{
  "id": {"S": "group1"},
	"name": {"S": "Group 1"}
}
ITEM
}
resource "aws_dynamodb_table_item" "group2" {
  table_name = aws_dynamodb_table.group.name
  hash_key   = aws_dynamodb_table.group.hash_key

  item = <<ITEM
{
  "id": {"S": "group2"},
	"name": {"S": "Group 2"}
}
ITEM
}

resource "aws_dynamodb_table_item" "user1" {
  table_name = aws_dynamodb_table.user.name
  hash_key   = aws_dynamodb_table.user.hash_key

  item = <<ITEM
{
  "id": {"S": "user1"},
	"name": {"S": "User 1"},
	"group_id": {"S": "group1"},
	"last_active": {"S": "2022-06-15"},
	"status": {"S": "INACTIVE"},
	"paired_with": {"S": "user3"},
	"group_id#status": {"S": "group1#INACTIVE"}
}
ITEM
}

resource "aws_dynamodb_table_item" "user2" {
  table_name = aws_dynamodb_table.user.name
  hash_key   = aws_dynamodb_table.user.hash_key

  item = <<ITEM
{
  "id": {"S": "user2"},
	"name": {"S": "User 2"},
	"group_id": {"S": "group2"},
	"last_active": {"S": "2022-06-16"},
	"status": {"S": "INACTIVE"},
	"group_id#status": {"S": "group2#INACTIVE"}
}
ITEM
}

resource "aws_dynamodb_table_item" "user3" {
  table_name = aws_dynamodb_table.user.name
  hash_key   = aws_dynamodb_table.user.hash_key

  item = <<ITEM
{
  "id": {"S": "user3"},
	"name": {"S": "User 3"},
	"group_id": {"S": "group1"},
	"last_active": {"S": "2022-01-01"},
	"status": {"S": "ACTIVE"},
	"paired_with": {"S": "user1"},
	"group_id#status": {"S": "group1#ACTIVE"}
}
ITEM
}

resource "aws_dynamodb_table_item" "user4" {
  table_name = aws_dynamodb_table.user.name
  hash_key   = aws_dynamodb_table.user.hash_key

  item = <<ITEM
{
  "id": {"S": "user4"},
	"name": {"S": "User 4"},
	"group_id": {"S": "group1"},
	"last_active": {"S": "2022-01-02"},
	"status": {"S": "INACTIVE"},
	"group_id#status": {"S": "group1#INACTIVE"}
}
ITEM
}

data "aws_iam_policy_document" "appsync" {
  statement {
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:Query",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:ConditionCheckItem",
    ]
    resources = [
      aws_dynamodb_table.group.arn,
      aws_dynamodb_table.user.arn,
    ]
  }
  statement {
    actions = [
      "dynamodb:Query",
    ]
    resources = [
      "${aws_dynamodb_table.user.arn}/index/groupId",
      "${aws_dynamodb_table.user.arn}/index/groupIdStatus",
    ]
  }
}

resource "aws_iam_role_policy" "appsync" {
  role   = aws_iam_role.appsync.id
  policy = data.aws_iam_policy_document.appsync.json
}

resource "aws_appsync_graphql_api" "appsync" {
  name                = "appsync_test"
  schema              = file("schema.graphql")
  authentication_type = "AWS_IAM"
}

resource "aws_appsync_datasource" "ddb_groups" {
  api_id           = aws_appsync_graphql_api.appsync.id
  name             = "ddb_groups"
  service_role_arn = aws_iam_role.appsync.arn
  type             = "AMAZON_DYNAMODB"
  dynamodb_config {
    table_name = aws_dynamodb_table.group.name
  }
}

resource "aws_appsync_datasource" "ddb_users" {
  api_id           = aws_appsync_graphql_api.appsync.id
  name             = "ddb_users"
  service_role_arn = aws_iam_role.appsync.arn
  type             = "AMAZON_DYNAMODB"
  dynamodb_config {
    table_name = aws_dynamodb_table.user.name
  }
}

# resolvers
resource "aws_appsync_resolver" "Query_groupById" {
  api_id            = aws_appsync_graphql_api.appsync.id
  type              = "Query"
  field             = "groupById"
  data_source       = aws_appsync_datasource.ddb_groups.name
  request_template  = <<EOF
{
	"version" : "2018-05-29",
	"operation" : "GetItem",
	"key" : {
		"id" : {"S": $util.toJson($ctx.args.id)}
	},
	"consistentRead" : true
}
EOF
  response_template = <<EOF
#if($ctx.error)
	$util.error($ctx.error.message, $ctx.error.type)
#end
$util.toJson($ctx.result)
EOF
}

resource "aws_appsync_resolver" "Mutation_pairUsers" {
  api_id            = aws_appsync_graphql_api.appsync.id
  type              = "Mutation"
  field             = "pairUsers"
  data_source       = aws_appsync_datasource.ddb_groups.name
  request_template  = <<EOF
{
  "version": "2018-05-29",
  "operation": "TransactWriteItems",
  "transactItems": [
    {
      "table": "${aws_dynamodb_table.user.name}",
      "operation": "UpdateItem",
      "key": {
        "id" : {"S": $util.toJson($ctx.args.user1)}
      },
			"update": {
				"expression": "SET #pairedWith = :user2",
				"expressionNames": {
					"#pairedWith": "paired_with"
				},
				"expressionValues": {
					":user2": {"S": $util.toJson($ctx.args.user2)}
				}
			},
			"condition": {
				"expression": "attribute_exists(#pk) AND attribute_not_exists(#pairedWith)",
				"expressionNames": {
					"#pk": "id"
				}
			}
    },
    {
      "table": "${aws_dynamodb_table.user.name}",
      "operation": "UpdateItem",
      "key": {
        "id" : {"S": $util.toJson($ctx.args.user2)}
      },
			"update": {
				"expression": "SET #pairedWith = :user1",
				"expressionNames": {
					"#pairedWith": "paired_with"
				},
				"expressionValues": {
					":user1": {"S": $util.toJson($ctx.args.user1)}
				}
			},
			"condition": {
				"expression": "attribute_exists(#pk) AND attribute_not_exists(#pairedWith)",
				"expressionNames": {
					"#pk": "id"
				}
			}
    }
  ]
}
EOF
  response_template = <<EOF
#if($ctx.error)
	$util.error($ctx.error.message, $ctx.error.type)
#end
$util.toJson($ctx.result.keys[0].id)
EOF
}

resource "aws_appsync_resolver" "Group_users" {
  api_id            = aws_appsync_graphql_api.appsync.id
  type              = "Group"
  field             = "users"
  data_source       = aws_appsync_datasource.ddb_users.name
  request_template  = <<EOF
{
	"version" : "2018-05-29",
	"operation" : "Query",
	"index": "groupId",
	"query": {
		"expression" : "#groupId = :groupId",
		"expressionNames": {
			"#groupId": "group_id"
		},
		"expressionValues" : {
			":groupId" : {"S": $util.toJson($ctx.source.id)}
		}
	},
	"limit": $util.toJson($ctx.args.count),
	"nextToken": $util.toJson($ctx.args.nextToken),
	"scanIndexForward": false
}
EOF
  response_template = <<EOF
#if($ctx.error)
	$util.error($ctx.error.message, $ctx.error.type)
#end
{
	"users": $utils.toJson($ctx.result.items),
	"nextToken": $util.toJson($ctx.result.nextToken)
}
EOF
}

resource "aws_appsync_resolver" "Group_users_filtered" {
  api_id            = aws_appsync_graphql_api.appsync.id
  type              = "Group"
  field             = "users_filtered"
  data_source       = aws_appsync_datasource.ddb_users.name
  request_template  = <<EOF
#if($util.isNull($ctx.args.status))
	{
		"version" : "2018-05-29",
		"operation" : "Query",
		"index": "groupId",
		"query": {
			"expression" : "#groupId = :groupId",
			"expressionNames": {
				"#groupId": "group_id"
			},
			"expressionValues" : {
				":groupId" : {"S": $util.toJson($ctx.source.id)}
			}
		},
		"limit": $util.toJson($ctx.args.count),
		"nextToken": $util.toJson($ctx.args.nextToken),
		"scanIndexForward": false
	}
#else
	{
		"version" : "2018-05-29",
		"operation" : "Query",
		"index": "groupIdStatus",
		"query": {
			"expression" : "#groupIdStatus = :groupIdStatus",
			"expressionNames": {
				"#groupIdStatus": "group_id#status"
			},
			"expressionValues" : {
				":groupIdStatus" : {"S": "$util.escapeJavaScript($ctx.source.id)#$util.escapeJavaScript($ctx.args.status)"}
			}
		},
		"limit": $util.toJson($ctx.args.count),
		"nextToken": $util.toJson($ctx.args.nextToken),
		"scanIndexForward": false
	}
#end
EOF
  response_template = <<EOF
#if($ctx.error)
	$util.error($ctx.error.message, $ctx.error.type)
#end
{
	"users": $utils.toJson($ctx.result.items),
	"nextToken": $util.toJson($ctx.result.nextToken)
}
EOF
}

resource "aws_appsync_resolver" "Group_users_filtered_inefficient" {
  api_id            = aws_appsync_graphql_api.appsync.id
  type              = "Group"
  field             = "users_filtered_inefficent"
  data_source       = aws_appsync_datasource.ddb_users.name
  request_template  = <<EOF
{
	"version" : "2018-05-29",
	"operation" : "Query",
	"index": "groupId",
	"query": {
		"expression" : "#groupId = :groupId",
		"expressionNames": {
			"#groupId": "group_id"
		},
		"expressionValues" : {
			":groupId" : {"S": $util.toJson($ctx.source.id)}
		}
	},
	#if(!$util.isNull($ctx.args.status))
		"filter": {
			"expression": "#status = :status",
			"expressionNames": {
				"#status": "status"
			},
			"expressionValues" : {
				":status" : {"S": $util.toJson($ctx.args.status)}
			}
		},
#end
	"limit": $util.toJson($ctx.args.count),
	"nextToken": $util.toJson($ctx.args.nextToken),
	"scanIndexForward": false
}
EOF
  response_template = <<EOF
#if($ctx.error)
	$util.error($ctx.error.message, $ctx.error.type)
#end
{
	"users": $utils.toJson($ctx.result.items),
	"nextToken": $util.toJson($ctx.result.nextToken)
}
EOF
}

resource "aws_appsync_resolver" "User_group" {
  api_id            = aws_appsync_graphql_api.appsync.id
  type              = "User"
  field             = "group"
  data_source       = aws_appsync_datasource.ddb_groups.name
  request_template  = <<EOF
{
	"version" : "2018-05-29",
	"operation" : "GetItem",
	"key": {
		"id": {"S": $util.toJson($ctx.source.group_id)}
	},
	"consistentRead": true
}
EOF
  response_template = <<EOF
#if($ctx.error)
	$util.error($ctx.error.message, $ctx.error.type)
#end
$util.toJson($ctx.result)
EOF
}

resource "aws_appsync_resolver" "User_paired_with" {
  api_id            = aws_appsync_graphql_api.appsync.id
  type              = "User"
  field             = "paired_with"
  data_source       = aws_appsync_datasource.ddb_users.name
  request_template  = <<EOF
#if($util.isNull($ctx.source.paired_with))
	#return
#end
{
	"version" : "2018-05-29",
	"operation" : "GetItem",
	"key": {
		"id": {"S": $util.toJson($ctx.source.paired_with)}
	},
	"consistentRead": true
}
EOF
  response_template = <<EOF
#if($ctx.error)
	$util.error($ctx.error.message, $ctx.error.type)
#end
$util.toJson($ctx.result)
EOF
}
