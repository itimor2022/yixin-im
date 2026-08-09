param(
    [Parameter(Mandatory = $true)]
    [string]$MessageId
)

$ErrorActionPreference = 'Stop'

$containerConfig = docker inspect genericim-mongodb | ConvertFrom-Json
$containerEnv = @{}
foreach ($entry in $containerConfig[0].Config.Env) {
    $separator = $entry.IndexOf('=')
    if ($separator -le 0) {
        continue
    }
    $containerEnv[$entry.Substring(0, $separator)] = $entry.Substring($separator + 1)
}

$mongoUser = [string]$containerEnv['MONGO_INITDB_ROOT_USERNAME']
$mongoPassword = [string]$containerEnv['MONGO_INITDB_ROOT_PASSWORD']
if (-not $mongoUser -or -not $mongoPassword) {
    throw 'MongoDB container credentials are not configured.'
}

$escapedMessageId = $MessageId.Replace('\', '\\').Replace("'", "\'")
$query = @"
const wanted = '$escapedMessageId';
for (const name of db.getMongo().getDBNames()) {
  const current = db.getSiblingDB(name);
  for (const collectionName of current.getCollectionNames().filter((value) => value.startsWith('messages'))) {
    const message = current.getCollection(collectionName).findOne({msg_id: wanted});
    if (!message) continue;
    print(EJSON.stringify({
      database: name,
      collection: collectionName,
      msg_id: message.msg_id,
      chat_id: message.chat_id,
      sender_id: message.sender_id,
      type: message.type,
      seq: message.seq,
      content: message.content,
      burn_after_read: message.burn_after_read,
      burn_duration: message.burn_duration,
      status: message.status,
      created_at: message.created_at
    }, null, 2));
  }
}
"@

$arguments = @(
    'exec',
    'genericim-mongodb',
    'mongosh',
    '--quiet',
    '--username',
    $mongoUser,
    '--password',
    $mongoPassword,
    '--authenticationDatabase',
    'admin',
    '--eval',
    $query
)

& docker @arguments
if ($LASTEXITCODE -ne 0) {
    throw "MongoDB query failed with exit code $LASTEXITCODE."
}
