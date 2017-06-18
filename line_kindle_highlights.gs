var CHANNEL_ACCESS_TOKEN = 'YourLineAccessToken';
var SERVER_ADDRESS = 'YourServerAddress:12345'

function doPost(e) {
  Logger.log('doPost')
  var events = JSON.parse(e.postData.contents).events;
  events.forEach (function(event) {
    if (event.type == "message") { lineReply(event); }
  });
}

function lineReply(e) {
  var postData = {
    "replyToken" : e.replyToken,
    "messages" : [
      {
        "type" : "text",
        "text" : "OK"
      }
    ]
  };

  var options = {
    "method" : "post",
    "headers" : {
      "Content-Type" : "application/json",
      "Authorization" : "Bearer " + CHANNEL_ACCESS_TOKEN
    },
    "payload" : JSON.stringify(postData)
  };

  UrlFetchApp.fetch("https://api.line.me/v2/bot/message/reply", options);
  UrlFetchApp.fetch(SERVER_ADDRESS);
}
