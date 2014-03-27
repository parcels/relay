# Load environment variables in development
dotenv = require 'dotenv'
dotenv.load()

Q       = require 'q'
_       = require 'underscore'
express = require 'express'
logger  = require 'winston'
r       = require 'rethinkdb'

RussianPost = require './lib/russianpost'
USPS = require './lib/usps'

# RethinkDB connection
rethinkDBOpts =
  host: process.env.RETHINKDB_HOST or 'localhost'
  port: process.env.RETHINKDB_PORT or 28015
  db:   process.env.RETHINKDB_DB   or 'parcels'
db = Q.nfcall r.connect, rethinkDBOpts
  .catch (err) -> logger.error err

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

app.get '/russianpost/:trackId', respond(RussianPost.fetchNormalized)
app.get '/usps/:trackId', respond(USPS.fetchNormalized)

port = process.env.PORT || 3000
app.listen port
logger.info "Listening on port #{port}"
