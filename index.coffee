# Load environment variables in development
dotenv = require 'dotenv'
dotenv.load()

Q       = require 'q'
_       = require 'underscore'
express = require 'express'
logger  = require 'winston'
r       = require 'rethinkdb'

carriers =
  russianpost: require './lib/russianpost'
  usps: require './lib/usps'

# RethinkDB connection
rethinkDBOpts =
  host: process.env.RETHINKDB_HOST or 'localhost'
  port: process.env.RETHINKDB_PORT or 28015
  db:   process.env.RETHINKDB_DB   or 'parcels'
db = Q.nfcall r.connect, rethinkDBOpts
  .catch (err) -> logger.error err

# Universal responder
# Unwraps a promise and renders the result
respond = (req, res) ->
  {carrier, trackId} = req.params
  carriers[carrier].fetchNormalized(trackId)
    .then (result) ->
      if result then res.json(result)
      else res.send 404
    .catch (err) ->
      logger.error err
      res.json 500, error: err


# Routing

app = express()
app.use express.compress()

app.get '/:carrier/:trackId', respond

port = process.env.PORT || 3000
app.listen port
logger.info "Listening on port #{port}"
