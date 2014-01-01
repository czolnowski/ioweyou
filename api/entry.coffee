moment = require 'moment'
config = require '../config'
auth = require '../lib/auth'
entryTable = require '../models/entry'
userTable = require '../models/user'
userManager = require '../managers/user'
clientTable = require '../models/userClient'
session = require '../models/session'


module.exports = (app) ->
  #GET
  app.get '/api/entry', auth.tokenAuth, list
  app.get '/api/entry/summary', auth.tokenAuth, summary
  app.get '/api/entry/count', auth.tokenAuth, count
  app.get '/api/entry/:id', auth.tokenAuth, one
  #PUT
  app.put '/api/entry',auth.tokenAuth, create
  #POST
  app.post '/api/entry/:id', auth.tokenAuth, modify
  app.post '/api/entry/accept/:id', auth.tokenAuth, accept
  app.post '/api/entry/reject/:id', auth.tokenAuth, reject
  #DELETE
  app.delete '/api/entry/:id', auth.tokenAuth, remove

one = (req, res) ->
  req.assert('id', 'Invalid entry ID').notEmpty().isInt()

  if not req.validationErrors()
    entryId = req.params.id
    userId = req.query.uid

    entryTable.getUserEntryById userId, entryId, (entry) ->
      if entry
        res.header "Content-Type", "application/json"
        res.send(entry)
      else
        res.status(404).send()
  else
    res.status(404).send()


list = (req, res) ->

  if req.query.limit
    req.assert('limit', {
      notEmpty: 'Required.',
      max: 'Maximum value is 100.',
      isInt: 'Integer expected.'
    }).max(100).isInt()

  if req.query.offset
    req.assert('offset', 'Invalid offset format. Expected integer').isInt()

  if req.query.from
    req.assert('from', 'Invalid from date format. Expected POSIX time').isInt()

  if req.query.to
    req.assert('to', 'Invalid from date format. Expected POSIX time').isInt()

  if req.query.contractor
    req.assert('contractor', 'Invalid contractor format. Expected integer.').isInt()

  if req.query.status
    req.assert('status', 'Invalid status format. Expected integer.').isInt()

  if req.query.order
    req.assert('order', 'Invalid order format. Expected asc or desc.').isIn(['asc', 'desc'])

  if not req.validationErrors()
    filters =
      limit: req.query.limit
      offset: req.query.offset
      from: req.query.from
      to: req.query.to
      contractor: req.query.contractor
      status: req.query.status
      order: req.query.order

    entryTable.getAll req.query.uid, filters, (entries) ->
      if entries
        res.header "Content-Type", "application/json"
        res.send(entries)
      else
        res.status(404).send()
  else
    res.status(404).send(req.validationErrors())

summary = (req, res) ->
  entryTable.getSummary req.query.uid, (summary) ->
    if summary
      res.header "Content-Type", "application/json"
      res.send(summary)
    else
      res.status(404).send()

count = (req, res) ->
  entryTable.getCount req.query.uid, (count) ->
    if count
      res.header "Content-Type", "application/json"
      res.send(count)
    else
      res.status(404).send()

create = (req, res) ->
  req.checkBody('name', 'Invalid name').notEmpty()
  req.checkBody('value', 'Invalid value').notEmpty().isFloat()

  if not req.validationErrors()

    userId = req.body.uid
    name = req.body.name
    contractors = req.body.contractors
    description = req.body.description
    value = req.body.value / (contractors.length + req.body.includeMe)

    userTable.friendshipsExists userId, userManager.usersToArrayOfIds(contractors), (exists) ->
      if exists
        console.log contractors
        for contractor in contractors
          userTable.getById contractor.id, (dbContractor) =>
            if dbContractor
              values =
                name: name
                description: description
                value: value
                status: 0
                lender_id: userId
                debtor_id: dbContractor.id
                created_at: moment().format('YYYY-MM-DD HH:mm:ss')
                updated_at: moment().format('YYYY-MM-DD HH:mm:ss')

              entryTable.create values, (statusCode, entryId)->
                if statusCode is not 200
                  res.status(statusCode).send {entryId: entryId}
                else
                  session.getUserData userId, (user) ->
                    console.log user
                    subject = "#{user.first_name} #{user.last_name} add dept to you."

                    clientTable.getByUserId dbContractor.id, (client)->
                      console.log 'Wysypanie push notyfikacji', client, dbContractor
                      if client
                        res.apn.createMessage()
                          .device(client.token)
                          .alert(subject)
                          .set('entryId', entryId)
                          .send()

                      res.mailer.send 'mails/creatingConfirmation', {
                        to: dbContractor.email,
                        subject: subject,
                        name: name,
                        description: description,
                        value: value,
                        contractor: dbContractor
                      }, (error) ->

            else
              res.status(404).send()

          res.status(200).send {isCreated: true}
      else
        res.send(404).send()
  else
    res.send(404).send()


accept = (req, res) ->
  req.assert('id', 'Invalid uid').notEmpty().isInt()

  if not req.validationErrors()
    entryId = req.params.id
    userId = req.body.uid

    entryTable.accept userId, entryId, (statusCode, isModified) ->
      if isModified
        entryTable.getById entryId, (entry)->
          userTable.getById entry.lender_id, (lender)->
            userTable.getById entry.debtor_id, (debtor)->

              subject = "#{debtor.first_name} #{debtor.last_name} accepted your entry."

              res.apn.createMessage()
                .device(device)
                .alert(subject)
                .send()

              res.mailer.send 'mails/acceptance', {
                to: 'p.kowalczuk.priv@gmail.com',
                #to: lender.email,
                subject: subject,
                entry: entry,
                debtor: debtor
              }, (error) ->


      res.status(statusCode).send {isModified: isModified}
  else
    res.status(404).send()


reject = (req, res) ->
  req.assert('id', 'Invalid uid').notEmpty().isInt()

  if not req.validationErrors()
    entryId = req.params.id
    userId = req.body.uid

    entryTable.reject userId, entryId, (statusCode, isModified) ->
      if isModified
        entryTable.getById entryId, (entry)->
          userTable.getById entry.lender_id, (lender)->
            userTable.getById entry.debtor_id, (debtor)->

              subject = "#{debtor.first_name} #{debtor.last_name} rejected your entry."

              res.apn.createMessage()
                .device(device)
                .alert(subject)
                .send()

              res.mailer.send 'mails/rejection', {
                to: 'p.kowalczuk.priv@gmail.com',
                #to: lender.email,
                subject: subject,
                entry: entry,
                debtor: debtor
                }, (error) ->

      res.status(statusCode).send {isModified: isModified}
  else
    res.status(404).send()


remove = (req, res) ->
  req.assert('id', 'Invalid uid').notEmpty().isInt()

  if not req.validationErrors()
    entryId = req.params.id
    userId = req.query.uid

    entryTable.remove userId, entryId, (statusCode, isModified) ->
      res.status(statusCode).send {isModified: isModified}
  else
    res.status(404).send()


modify = (req, res) ->
  req.assert('id', 'Invalid uid').notEmpty().isInt()
  req.checkBody('name', 'Invalid uid').notEmpty()
  req.checkBody('value', 'Invalid uid').notEmpty().isInt()

  if not req.validationErrors()
    entryId = req.params.id
    userId = req.body.uid
    name = req.body.name
    description = req.body.description
    value = req.body.value

    values =
      name: name
      description: description
      value: value
      updated_at: moment().format('YYYY-MM-DD HH:mm:ss')

    entryTable.modify userId, entryId, values, (statusCode, isModified) ->
      if isModified
        entryTable.getById entryId, (entry)->
          userTable.getById entry.lender_id, (lender)->
            userTable.getById entry.debtor_id, (debtor)->

              subject = "#{debtor.first_name} #{debtor.last_name} modified your entry."

              res.apn.createMessage()
                .device(device)
                .alert(subject)
                .send()

              res.mailer.send 'mails/modification', {
                to: lender.email,
                subject: subject,
                entry: entry,
                debtor: debtor
                }, (error) ->

      res.status(statusCode).send {isModified: isModified}
  else
    res.status(400).send()


