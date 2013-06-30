Presenters = new Meteor.Collection "presenters"
HistoryData = new Meteor.Collection "histories"

reset = ->
  Meteor.call("remove_all")
  history_data_id = HistoryData.insert {data: []}
  Session.set "history_data_id", history_data_id

if Meteor.is_client
  last_render_time = 0

  navigator.getUserMedia = navigator.getUserMedia or navigator.webkitGetUserMedia or navigator.mozGetUserMedia or navigator.msGetUserMedia
  window.URL = window.URL or window.webkitURL or window.mozURL or window.msURL
  window.AudioContext = window.AudioContext or window.webkitAudioContext or window.mozAudioContext or window.msAudioContext

  width = 768
  height = 192
  refresh_msec = 3000
  recorder_id = null

  initialize = ->
    # canvas
    frequencyElement = document.getElementById("frequency")
    presentElement = document.getElementById("present")
    historyElement = document.getElementById("history")

    frequencyContext = frequencyElement.getContext("2d")
    frequencyElement.width = width
    frequencyElement.height = height

    presentContext = presentElement.getContext("2d")
    presentElement.width = width
    presentElement.height = height

    historyContext = historyElement.getContext("2d")
    historyElement.width = width
    historyElement.height = height

    # audio
    audioElement = document.getElementById("audio")

    navigator.getUserMedia
      audio: true
    , ((stream) ->
      url = URL.createObjectURL(stream)
      audioElement.src = url
      audioContext = new AudioContext()

      mediastreamsource = audioContext.createMediaStreamSource(stream)
      analyser = audioContext.createAnalyser()

      # データ保存領域
      frequencyData = new Uint8Array(analyser.frequencyBinCount)
      mediastreamsource.connect analyser

      animation = ->
        # get data
        analyser.getByteFrequencyData frequencyData

        # frequency
        frequencyContext.clearRect 0, 0, width, height
        frequencyContext.beginPath()
        frequencyContext.moveTo 0, height - frequencyData[0]
        i = 1
        l = frequencyData.length

        sum = 0
        while i < l
          frequencyContext.lineTo i, height - frequencyData[i]
          sum += frequencyData[i]
          i++
        frequencyContext.stroke()

        # time scale
        history = HistoryData.findOne()
        historyData = history.data
        historyData.push sum

        scale_x = (x) ->
          Math.ceil(x / historyData.length * width)

        date = new Date()
        if date.getTime() - last_render_time > refresh_msec
          last_render_time = date.getTime()

          historyContext.clearRect 0, 0, width, height

          presenter = Presenters.findOne(Session.get("selected_presenter"))
          if presenter
            historyContext.beginPath()
            historyContext.fillStyle = 'rgb(204,255,102)'
            x = scale_x(presenter.count - width)
            w = scale_x(width)
            historyContext.fillRect x, 0, w, height

          maxHistory = Math.max.apply(null, historyData)
          tic = Math.ceil(historyData.length / width)
          i = 1

          historyContext.beginPath()
          historyContext.moveTo 0, height - historyData[0]/maxHistory*height
          while i < historyData.length
            if tic is 1
              history_index = i
              history_value = historyData[i]
            else
              # いくつかのサンプルを平均して表示処理の負荷を下げる
              history_index = scale_x(i)
              sum = 0
              for j in [i..i+(tic-1)]
                sum += historyData[j]
              history_value = Math.ceil(sum / tic)

            historyContext.lineTo history_index, height - history_value/maxHistory*height
            i += tic

          historyContext.stroke()

        # save
        HistoryData.update(history._id, {data: historyData})

        # sliding window
        present_index = historyData.length - 1
        if present_index <= width
          presentData = historyData
        else
          presentData = historyData.slice present_index - width, present_index

        maxPresent = Math.max.apply(null, presentData)
        presentContext.clearRect 0, 0, width, height
        presentContext.beginPath()
        presentContext.moveTo 0, height - presentData[0]/maxPresent*height

        i = 1
        while i < presentData.length
          presentContext.lineTo i, height - presentData[i]/maxPresent*height
          i++
        presentContext.stroke()

        # render
        requestAnimationFrame animation

      animation()

    ), (e) ->
      console.log e

  # 初期化
  window.addEventListener "load", initialize, false

  # viewから読む値
  Template.crap.sort_by_time = ->
    Session.get("sort_by_time")

  Template.crap.presenters = ->
    Presenters.find({}, {sort: (if Template.crap.sort_by_time() then {time:1, score: -1} else {score: -1, time: 1}) })

  Template.crap.selected_name = ->
    presenter = Presenters.findOne(Session.get("selected_presenter"))
    presenter && presenter.name

  Template.presenter.selected = ->
    if Session.equals("selected_presenter", this._id) then "selected" else ''

  Template.crap.events = {
    # add button
    'click input[name=add]': ->
      save_exciting_score()

    # enter key
    'keypress input[name=name]': (event)->
      save_exciting_score() if event.which is 13

    # sort
    'click a#sort_by_time': ->
      Session.set "sort_by_time", true

    'click a#sort_by_score': ->
      Session.set "sort_by_time", false

    # リセット
    'click input.reset': ->
      reset() if confirm()
      recorder_id = Meteor.uuid()
      Session.set "recorder_id", recorder_id
  }

  save_exciting_score = ->
    date = new Date()
    Presenters.insert
      name: $("input[name=name]").val()
      time: date.toLocaleTimeString()
      score: exciting_score()
      count: HistoryData.findOne().data.length

  confirm = ->
    if window.confirm("本当に良いの？")
      true
    else
      false

  exciting_score = ->
    history = HistoryData.findOne()
    historyData = history.data
    present_index = historyData.length - 1
    if present_index <= width
      presentData = historyData
    else
      presentData = historyData.slice present_index - width, present_index

    Math.max.apply(null, presentData)

  Template.presenter.events = {
    'click': ->
      Session.set("selected_presenter", this._id)

    'click a.delete': ->
      Presenters.remove {_id: this._id} if confirm()
    }

if Meteor.is_server
  Meteor.startup(->
    if HistoryData.find().count() is 0
      history_data_id = HistoryData.insert {data: []}
      Session.set "history_data_id", history_data_id
  )

  Meteor.methods
    remove_all: ->
      HistoryData.remove {}
      Presenters.remove {}
