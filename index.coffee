dotenv = require 'dotenv'
dotenv.load()

express = require 'express'
app = express()

app.use express.compress()

soap    = require 'soap'
Q       = require 'q'
http    = require 'q-io/http'
xml2js  = require 'xml2json'


fetchRussianPost = (client) -> (trackId) ->
  message =
    Barcode: trackId
    MessageType: 0
  Q.nfcall client.GetOperationHistory, message

fetchUSPS = (trackId) ->
  url = "http://production.shippingapis.com/ShippingAPI.dll?API=TrackV2&XML=
    <TrackFieldRequest USERID=\"#{process.env.USPS_USER_ID}\">
      <TrackID ID=\"#{trackId}\"></TrackID>
    </TrackFieldRequest>"
  http.request url
    .then (response) -> response.body.read()
    .then (body) ->  Q xml2js.toJson(body, object: true)


respond = (fn) -> (req, res) ->
  fn(req.params.trackId)
    .then (result) ->
      if result then res.json result
      else res.send 404
    .catch (err) ->
      console.error err
      res.json 500, error: err


wsdl = './lib/russianpost/wsdl/russianpost_1.wsdl'
Q.nfcall soap.createClient, wsdl
  .then (client) ->
    app.get '/russianpost/:trackId', respond(fetchRussianPost client)
    console.log '[INFO] RussianPost client established'
  .catch (err) ->
    console.error err
  .done()

app.get '/usps/:trackId', respond(fetchUSPS)
console.log '[INFO] USPS client established'

port = process.env.PORT || 3000

app.listen port
console.log "[INFO] Listening on port #{port}"
