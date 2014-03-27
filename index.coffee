soap    = require 'soap'
Q       = require 'q'
http    = require 'q-io/http'
xml2js  = require 'xml2json'
express = require 'express'
logger  = require 'winston'
r       = require 'rethinkdb'
dotenv  = require 'dotenv'

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


# Fetchers
# Send requests to APIs and return JS objects wrapped in promises

fetchRussianPost = (trackId) ->
  message =
    Barcode: trackId
    MessageType: 0
  russianPostClient.then (client) ->
    Q.nfcall client.GetOperationHistory, message

fetchUSPS = (trackId) ->
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

app.get '/russianpost/:trackId', respond(fetchRussianPost)
app.get '/usps/:trackId', respond(fetchUSPS)

port = process.env.PORT || 3000
app.listen port
logger.info "Listening on port #{port}"
