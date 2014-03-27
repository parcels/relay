dotenv = require 'dotenv'
dotenv.load()

express = require 'express'
app = express()

app.use express.compress()

soap    = require 'soap'
Q       = require 'q'
http    = require 'q-io/http'
xml2js  = require 'xml2json'


fetchRussianPost = (client) -> (req, res) ->
  message =
    Barcode: req.params.barcode
    MessageType: 0

  Q.nfcall client.GetOperationHistory, message
    .then (result) ->
      if result then res.json result
      else res.send 404
    .catch (err) ->
      console.error err
      res.json 500, error: err


fetchUSPS = (req, res) ->
  query =
    "<TrackFieldRequest USERID=\"#{process.env.USPS_USER_ID}\">
      <TrackID ID=\"#{req.params.barcode}\"></TrackID>
    </TrackFieldRequest>"

  url = "http://production.shippingapis.com/ShippingAPI.dll?API=TrackV2&XML=#{query}"

  http.request url
    .then (response) ->
      response.body.read()
    .then (body) ->
      res.json xml2js.toJson(body, object: true)
    .catch (err) ->
      console.log err
      res.send 500, error: err


wsdl = './lib/russianpost/wsdl/russianpost_1.wsdl'
Q.nfcall soap.createClient, wsdl
  .then (client) ->
    app.get '/russianpost/:barcode', fetchRussianPost(client)
    console.log '[INFO] RussianPost client established'
  .catch (err) ->
    console.error err
  .done()

app.get '/usps/:barcode', fetchUSPS
console.log '[INFO] USPS client established'

port = process.env.PORT || 3000

app.listen port
console.log "[INFO] Listening on port #{port}"
