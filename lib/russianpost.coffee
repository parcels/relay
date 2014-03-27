Q      = require 'q'
_      = require 'underscore'
logger = require 'winston'
non    = require 'nested-or-nothing'
soap   = require 'soap'

{compact, partial} = _

# Russian Post SOAP client
wsdl = './lib/russianpost/wsdl/russianpost_1.wsdl'
russianPostClient = Q.nfcall soap.createClient, wsdl
  .catch (err) -> logger.error err

composeMessage = (trackId) ->
  Barcode: trackId
  MessageType: 0

fetch = (trackId) ->
  russianPostClient.then (client) ->
    Q.nfcall client.GetOperationHistory, composeMessage(trackId)
      .get 0

normalize = (response) ->
  response.historyRecord.map (operation) ->
    path = partial non, operation

    operType = path 'OperationParameters', 'OperType', 'Name'
    operAttr = path 'OperationParameters', 'OperAttr', 'Name'

    trackId:   path 'ItemParameters', 'Barcode'
    time:      path 'OperationParameters', 'OperDate'
    zip:       path 'AddressParameters', 'OperationAddress', 'Index'
    location:  path 'AddressParameters', 'OperationAddress', 'Description'
    message:   compact([operType, operAttr]).join ': '

fetchNormalized = (trackId) ->
  fetch(trackId).then normalize

module.exports = {
  fetch, normalize, fetchNormalized
}
