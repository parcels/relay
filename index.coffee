dotenv = require 'dotenv'
dotenv.load()

express = require 'express'
app = express()

app.use express.compress()

soap    = require 'soap'
_       = require 'underscore'
request = require 'request'
xml2js  = require 'xml2json'

wsdl  = './lib/russianpost/wsdl/russianpost_1.wsdl'

soap.createClient wsdl, (err, client) ->
  if err
    console.error err
  else
    fetchRussianPost = (req, res) ->
      message =
        Barcode: req.params.barcode
        MessageType: 0

      client.GetOperationHistory message, (err, result) ->
        if err
          console.error err
          res.send 500
        else if result
          res.json result
        else
          res.send 404

    fetchUSPS = (req, res) ->
      query = 
        "<TrackFieldRequest USERID=\"#{process.env.USPS_USER_ID}\">
          <TrackID ID=\"#{req.params.barcode}\"></TrackID>
        </TrackFieldRequest>"

      url = "http://production.shippingapis.com/ShippingAPI.dll?API=TrackV2&XML=#{query}"

      request url, (err, response, body) ->
        if err
          console.log err
          res.send 500
        else
          res.json xml2js.toJson(body, object: true)

    app.get '/parcels/russianpost/:barcode', fetchRussianPost
    app.get '/parcels/usps/:barcode', fetchUSPS

    port = process.env.PORT || 3000

    app.listen port
    console.log "[INFO] Listening on port #{port}"
