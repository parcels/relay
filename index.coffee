Q       = require 'q'
dotenv  = require 'dotenv'
express = require 'express'
http    = require 'q-io/http'
logger  = require 'winston'
non     = require 'nested-or-nothing'
r       = require 'rethinkdb'
soap    = require 'soap'
xml2js  = require 'xml2json'

# Load environment variables in development
dotenv.load()

# Russian Post SOAP client
wsdl = './lib/russianpost/wsdl/russianpost_1.wsdl'
russianPostClient = Q.nfcall soap.createClient, wsdl
  .catch (err) -> logger.error err

# RethinkDB connection
rethinkDBOpts =
  host: process.env.RETHINKDB_HOST or 'localhost'
  port: process.env.RETHINKDB_PORT or 28015
  db:   process.env.RETHINKDB_DB   or 'parcels'
db = Q.nfcall r.connect, rethinkDBOpts
  .catch (err) -> logger.error err


RussianPost =
  fetch: (trackId) ->
    message =
      Barcode: trackId
      MessageType: 0
    russianPostClient.then (client) ->
      Q.nfcall client.GetOperationHistory, message
        .get 0

  normalize: (response) ->
    response.historyRecord.map (operation) ->
      operType = non operation, 'OperationParameters', 'OperType', 'Name'
      operAttr = non operation, 'OperationParameters', 'OperAttr', 'Name'

      trackId:  non operation, 'ItemParameters', 'Barcode'
      time:     non operation, 'OperationParameters', 'OperDate'
      zip:      non operation, 'AddressParameters', 'OperationAddress', 'Index'
      location: non operation, 'AddressParameters', 'OperationAddress', 'Description'
      message:  if operAttr? then [operType, operAttr].join ': ' else operType



USPS =
  fetch: (trackId) ->
    url = "http://production.shippingapis.com/ShippingAPI.dll?API=TrackV2&XML="
    message =
      TrackFieldRequest:
        USERID: process.env.USPS_USER_ID
        TrackID:
          ID: trackId
    http.request url + xml2js.toXml(message)
      .then (response) -> response.body.read()
      .then (body) -> Q xml2js.toJson(body, object: true)


# Universal responder
# Unwraps a promise and renders the result
respond = (fn) -> (req, res) ->
  fn(req.params.trackId)
    .then (result) ->
      if result then res.json result
      else res.send 404
    .catch (err) ->
      logger.error err
      res.json 500, error: err


# Routing

app = express()
app.use express.compress()

app.get '/russianpost/:trackId', respond(RussianPost.fetch)
app.get '/usps/:trackId', respond(USPS.fetch)

port = process.env.PORT || 3000
app.listen port
logger.info "Listening on port #{port}"
