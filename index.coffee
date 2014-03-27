Q       = require 'q'
_       = require 'underscore'
dotenv  = require 'dotenv'
express = require 'express'
http    = require 'q-io/http'
logger  = require 'winston'
moment  = require 'moment'
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
      message:  _.compact([operType, operAttr]).join ': '



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
      .then (body) -> Q xml2js.toJson(body, object: true, sanitize: false)

  normalize: (response) ->
    e2n = emptyObjectToNull = (val) ->
      if _.isObject(val) and _.isEmpty(val) then null
      else val

    trackId = non response, 'TrackResponse', 'TrackInfo', 'ID'

    (response.TrackResponse.TrackInfo.TrackDetail or []).map (operation) ->
      {EventDate, EventTime, EventCity, EventState, EventCountry, EventZIPCode} = operation

      trackId:  trackId
      time:     moment(_.compact([e2n EventDate, e2n EventTime]).join ' ').format()
      location: _.compact([e2n(EventCity), e2n(EventState), e2n(EventCountry)]).join ', '
      zip:      if e2n(EventZIPCode) then "#{EventZIPCode}" else undefined
      message:  e2n operation.Event




# Universal responder
# Unwraps a promise and renders the result
respond = (fetchFn, normalizeFn) -> (req, res) ->
  fetchFn(req.params.trackId)
    .then (result) ->
      if result then res.json normalizeFn(result)
      else res.send 404
    .catch (err) ->
      logger.error err
      res.json 500, error: err


# Routing

app = express()
app.use express.compress()

app.get '/russianpost/:trackId', respond(RussianPost.fetch, RussianPost.normalize)
app.get '/usps/:trackId', respond(USPS.fetch, USPS.normalize)

port = process.env.PORT || 3000
app.listen port
logger.info "Listening on port #{port}"
