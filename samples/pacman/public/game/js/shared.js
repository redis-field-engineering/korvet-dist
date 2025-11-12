function loadHighestScore(player, callback) {
	// Stubbed out for Korvet demo - no ksqlDB queries
	var highestScore = 0;
	callback(highestScore);
}

function loadSummaryStats(callback) {
	// Stubbed out for Korvet demo - no ksqlDB queries
	var highestScore = 0;
	var usersSet = [];
	callback(highestScore, usersSet);
}


function sendksqlDBStmt(request, ksqlQuery){
	var query = {};
	query.ksql = ksqlQuery;
	query.endpoint = "ksql";
	request.open('POST', KSQLDB_QUERY_API, true);
	request.setRequestHeader('Accept', 'application/json');
	request.setRequestHeader('Content-Type', 'application/json');
	request.send(JSON.stringify(query));
}

function sendksqlDBQuery(request, ksqlQuery){
	var query = {};
	query.sql = ksqlQuery;
	query.endpoint = "query-stream";
	request.open('POST', KSQLDB_QUERY_API, true);
	request.setRequestHeader('Accept', 'application/json');
	request.setRequestHeader('Content-Type', 'application/json');
	request.send(JSON.stringify(query));
}

function getScoreboardJson(callback,userList) {
	// Stubbed out for Korvet demo - no ksqlDB queries
	var playersScores = [];
	callback(playersScores);
}

