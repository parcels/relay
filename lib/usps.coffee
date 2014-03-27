Q      = require 'q'
_      = require 'underscore'
http   = require 'q-io/http'
moment = require 'moment'
non    = require 'nested-or-nothing'
x2j    = require 'xml2json'

{object, map, pairs, isEmpty, compact} = _

userId = process.env.USPS_USER_ID
url = 'http://production.shippingapis.com/ShippingAPI.dll?API=TrackV2&XML='

composeMessage = (trackId) ->
  TrackFieldRequest:
    USERID: userId
    TrackID:
      ID: trackId

fetch = (trackId) ->
  http.request url + x2j.toXml(composeMessage trackId)
    .then (response) -> response.body.read()
    .then (body)     -> x2j.toJson(body, object: true, sanitize: false)

normalize = (response) ->
  trackInfo = non(response, 'TrackResponse', 'TrackInfo') or {}

  (trackInfo.TrackDetail or []).map (operation) ->
    e = object map pairs(operation), (pair) ->
      [k, v] = pair
      [k.slice(5) or k, if isEmpty v then '' else v]

    trackId:  trackInfo.ID
    time:     moment("#{e.Date} #{e.Time}").format()
    location: compact([e.City, e.State, e.Country]).join ', '
    zip:      e.ZIPCode
    message:  e.Event

fetchNormalized = (trackId) ->
  fetch(trackId).then normalize

module.exports = {
  fetch, normalize, fetchNormalized
}
