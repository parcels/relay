# Load environment variables in development
dotenv = require 'dotenv'
dotenv.load()

Q       = require 'q'
_       = require 'underscore'
express = require 'express'
logger  = require 'winston'
r       = require 'rethinkdb'
soap    = require 'soap'
USPS    = require './lib/usps'

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
      message:  _.compact([operType, operAttr]).join ': '



# Universal responder
# Unwraps a promise and renders the result
respond = (fn) -> (req, res) ->
  fn(req.params.trackId)
    .then (result) ->
      if result then res.json(result)
      else res.send 404
    .catch (err) ->
      logger.error err
      res.json 500, error: err


# Routing

app = express()
app.use express.compress()

app.get '/russianpost/:trackId', respond(RussianPost.fetch)
app.get '/usps/:trackId', respond(USPS.fetchNormalized)

port = process.env.PORT || 3000
app.listen port
logger.info "Listening on port #{port}"
