import { DynamoDBClient, QueryCommand } from "@aws-sdk/client-dynamodb";

const client = new DynamoDBClient();

const sendReq = (Limit, ExclusiveStartKey) => client.send(new QueryCommand({
	TableName: process.env.TABLE,
	IndexName: "groupId",
	KeyConditionExpression: "#groupId = :groupId",
	ExpressionAttributeNames: {"#groupId": "group_id", "#status": "status"},
	ExpressionAttributeValues: {
		":groupId": {S: "group1"},
		":status": {S: "ACTIVE"},
	},
	FilterExpression: "#status = :status",
	ScanIndexForward: false,
	Limit,
	ExclusiveStartKey,
}));

const fetchItemsAndPrintResults = async (Limit, ExclusiveStartKey) => {
	const res = await sendReq(Limit, ExclusiveStartKey);
	console.log({
		Items: res.Items.length,
		LastEvaluatedKey: !!res.LastEvaluatedKey,
		Count: res.Count,
		ScannedCount: res.ScannedCount,
	});
	if (res.LastEvaluatedKey) {
		await fetchItemsAndPrintResults(Limit, res.LastEvaluatedKey);
	}
}

console.log("no Limit");
await fetchItemsAndPrintResults();
console.log("Limit: 1");
await fetchItemsAndPrintResults(1);
console.log("Limit: 2");
await fetchItemsAndPrintResults(2);
console.log("Limit: 3");
await fetchItemsAndPrintResults(3);
console.log("Limit: 4");
await fetchItemsAndPrintResults(4);

