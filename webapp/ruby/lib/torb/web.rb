require 'json'
require 'sinatra/base'
require 'erubi'
require 'mysql2'
require 'mysql2-cs-bind'
require 'digest/md5'
require 'securerandom'

SHEETS = [
  *(['S'] * 50).each_with_index.map { |rank, index| {rank: rank, num: index + 1} },
  *(['A'] * 150).each_with_index.map { |rank, index| {rank: rank, num: index + 1} },
  *(['B'] * 300).each_with_index.map { |rank, index| {rank: rank, num: index + 1} },
  *(['C'] * 500).each_with_index.map { |rank, index| {rank: rank, num: index + 1} },
]

PRICES = {
  'S' => 5000,
  'A' => 3000,
  'B' => 1000,
  'C' => 0,
}

SHEET_TOTAL = {
  'S' => 50,
  'A' => 150,
  'B' => 300,
  'C' => 500,
}

module Torb
  class Web < Sinatra::Base
    configure :development do
      require 'sinatra/reloader'
      register Sinatra::Reloader
    end

    set :root, File.expand_path('../..', __dir__)
    set :sessions, key: 'torb_session', expire_after: 3600
    set :session_secret, 'tagomoris'
    set :protection, frame_options: :deny

    set :erb, escape_html: true

    set :login_required, ->(value) do
      condition do
        if value && !get_login_user
          halt_with_error 401, 'login_required'
        end
      end
    end

    set :admin_login_required, ->(value) do
      condition do
        if value && !get_login_administrator
          halt_with_error 401, 'admin_login_required'
        end
      end
    end

    before '/api/*|/admin/api/*' do
      content_type :json
    end

    helpers do
      def db
        Thread.current[:db] ||= Mysql2::Client.new(
          host: ENV['DB_HOST'],
          port: ENV['DB_PORT'],
          username: ENV['DB_USER'],
          password: ENV['DB_PASS'],
          database: ENV['DB_DATABASE'],
          database_timezone: :utc,
          cast_booleans: true,
          reconnect: true,
          #init_command: 'SET SESSION sql_mode="STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION"',
        )
      end

      def get_events(where = nil)
        where ||= ->(e) { e['public_fg'] }

        # db.query('BEGIN')
        # begin
          events = db.query('SELECT * FROM events ORDER BY id ASC').select(&where)
          # if events.size < 5
           sql = <<-SQL
             SELECT sheet_id, event_id, reserved_at
             FROM sheetstates
             /* WHERE event_id IN (?) */
           SQL
           rows = db.xquery(sql, [if events.size == 0 then -999999 else events.map { |e| e['id'] } end]).to_a || []
           states = {}
           rows.each do | row |
             states[row['event_id']] = states[row['event_id']] || []
             states[row['event_id']].push({ 'sheet_id' => row['sheet_id'], 'reserved_at' => row['reserved_at'] })
           end
          # end

          event_data = events.map do |event|
            event['total']   = 0
            event['remains'] = 0
            event['sheets'] = {}
            %w[S A B C].each do |rank|
              event['sheets'][rank] = { 'total' => 0, 'remains' => 0, 'detail' => [] }
            end
            if events.size >= 5
              sql = <<-SQL
              SELECT sheet_id, event_id, reserved_at
               FROM sheetstates
               WHERE event_id = ?
             SQL
             # states = db.xquery(sql, event['id']).to_a
            end

            SHEETS.each_with_index do |sheet_data, index|
              sheet_id = index + 1
              sheet = {
                'price' => PRICES[sheet_data[:rank]],
                'rank' => sheet_data[:rank],
                'num' => sheet_data[:num],
              }
              event['sheets'][sheet['rank']]['price'] ||= event['price'] + sheet['price']
              event['total'] += 1
              event['sheets'][sheet['rank']]['total'] += 1

              state = (states[event['id']] || []).detect { |r| r['sheet_id'] == sheet_id } # && r['event_id'] == event['id'] }
              if state
                sheet['reserved']    = true
                sheet['reserved_at'] = state['reserved_at'].to_i
              else
                event['remains'] += 1
                event['sheets'][sheet['rank']]['remains'] += 1
              end

              event['sheets'][sheet['rank']]['detail'].push(sheet)

              sheet.delete('id')
              sheet.delete('price')
              sheet.delete('rank')
            end

            event['public'] = event.delete('public_fg')
            event['closed'] = event.delete('closed_fg')

            event['sheets'].each { |sheet| sheet.delete('detail') }
            event
            p event
          end
          # db.query('COMMIT')
        # rescue
          # db.query('ROLLBACK')
        # end

        p event_data
        event_data
      end

      def get_event(event_id, login_user_id = nil)
        event = db.xquery('SELECT * FROM events WHERE id = ?', event_id).first
        return unless event

        # zero fill
        event['total']   = 0
        event['remains'] = 0
        event['sheets'] = {}
        %w[S A B C].each do |rank|
          event['sheets'][rank] = { 'total' => 0, 'remains' => 0, 'detail' => [] }
        end

        sql = <<-SQL
          SELECT *
          FROM sheetstates
          WHERE event_id = ?
        SQL
        states = db.xquery(sql, event['id']).to_a
        SHEETS.each_with_index do |sheet_data, index|
          sheet_id = index + 1
          sheet = {
            'price' => PRICES[sheet_data[:rank]],
            'rank' => sheet_data[:rank],
            'num' => sheet_data[:num],
          }
          event['sheets'][sheet['rank']]['price'] ||= event['price'] + sheet['price']
          event['total'] += 1
          event['sheets'][sheet['rank']]['total'] += 1

          state = states.detect { |r| r['sheet_id'] == sheet_id }
          if state
            sheet['mine']        = true if login_user_id && state['user_id'] == login_user_id
            sheet['reserved']    = true
            sheet['reserved_at'] = state['reserved_at'].to_i
          else
            event['remains'] += 1
            event['sheets'][sheet['rank']]['remains'] += 1
          end

          event['sheets'][sheet['rank']]['detail'].push(sheet)

          sheet.delete('id')
          sheet.delete('price')
          sheet.delete('rank')
        end

        event['public'] = event.delete('public_fg')
        event['closed'] = event.delete('closed_fg')

        event
      end

      def sanitize_event(event)
        sanitized = event.dup  # shallow clone
        sanitized.delete('price')
        sanitized.delete('public')
        sanitized.delete('closed')
        sanitized
      end

      def get_login_user
        user_id = session[:user_id]
        return unless user_id
        db.xquery('SELECT id, nickname FROM users WHERE id = ?', user_id).first
      end

      def get_login_administrator
        administrator_id = session['administrator_id']
        return unless administrator_id
        db.xquery('SELECT id, nickname FROM administrators WHERE id = ?', administrator_id).first
      end

      def validate_rank(rank)
        %w[S A B C].include?(rank)
      end

      def body_params
        @body_params ||= JSON.parse(request.body.tap(&:rewind).read)
      end

      def halt_with_error(status = 500, error = 'unknown')
        halt status, { error: error }.to_json
      end

      def render_report_csv(reports)
        #reports = reports.sort_by { |report| report[:sold_at] }

        keys = %i[reservation_id event_id rank num price user_id sold_at canceled_at]
        body = keys.join(',')
        body << "\n"
        reports.each do |report|
          body << report.values_at(*keys).join(',')
          body << "\n"
        end

        headers({
          'Content-Type'        => 'text/csv; charset=UTF-8',
          'Content-Disposition' => 'attachment; filename="report.csv"',
        })
        body
      end
    end

    get '/' do
      @user   = get_login_user
      @events = get_events.map(&method(:sanitize_event))
      erb :index
    end

    get '/initialize' do
      system "../../db/init.sh"

      status 204
    end

    post '/api/users' do
      nickname   = body_params['nickname']
      login_name = body_params['login_name']
      password   = body_params['password']

      db.query('BEGIN')
      begin
        duplicated = db.xquery('SELECT * FROM users WHERE login_name = ?', login_name).first
        if duplicated
          db.query('ROLLBACK')
          halt_with_error 409, 'duplicated'
        end

        db.xquery('INSERT INTO users (login_name, pass_hash, nickname) VALUES (?, SHA2(?, 256), ?)', login_name, password, nickname)
        user_id = db.last_id
        db.query('COMMIT')
      rescue => e
        warn "rollback by: #{e}"
        db.query('ROLLBACK')
        halt_with_error
      end

      status 201
      { id: user_id, nickname: nickname }.to_json
    end

    get '/api/users/:id', login_required: true do |user_id|
      user = db.xquery('SELECT id, nickname FROM users WHERE id = ?', user_id).first
      if user['id'] != get_login_user['id']
        halt_with_error 403, 'forbidden'
      end

      total_price = 0
      sql = <<-SQL
        SELECT *
        FROM reservations
        WHERE user_id = ?
        ORDER BY updated_at
        DESC LIMIT 5
      SQL
      rows = db.xquery(sql, user['id'])
      reserved_events = db.xquery('SELECT * FROM events WHERE id IN (?)', [if rows.size == 0 then -999999 else rows.map { |r| r['event_id'] } end])
      recent_reservations = rows.map do |row|
        rank = SHEETS[row['sheet_id'].to_i - 1][:rank]
        num = SHEETS[row['sheet_id'].to_i - 1][:num]
        event = reserved_events.detect { |ev| ev['id'] == row['event_id'] }
        price = event['price'] + PRICES[rank]
        event_data = {
          closed: event['closed_fg'],
          public: event['public_fg'],
          id: row['event_id'],
          price: event['price'],
          title: event['title'],
        }

        total_price += price unless row['canceled_at']

        {
          id:          row['id'],
          event:       event_data,
          sheet_rank:  rank,
          sheet_num:   num,
          price:       price,
          reserved_at: row['reserved_at'].to_i,
          canceled_at: row['canceled_at']&.to_i,
        }
      end

      user['recent_reservations'] = recent_reservations
      user['total_price'] = total_price

      sql = <<-SQL
        SELECT e.*
        FROM events e
        LEFT JOIN reservations r
          ON r.event_id = e.id
        WHERE r.user_id = ?
        GROUP BY r.event_id
        ORDER BY MAX(r.updated_at)
        DESC LIMIT 5
      SQL
      events = db.xquery(sql, user['id'])
      recent_sheets = db.xquery('SELECT * FROM sheetcounts WHERE event_id IN (?)', [if events.size == 0 then -999999 else events.map { |r| r['id'] } end]).map { |r| { event_id: r['event_id'], rank: r['rank'], count: r['count'] } }
      recent_sheets = events.map { |row| PRICES.map { |ra, pr| { 'event_id': row['id'], 'rank': ra, 'count': 0 } } }.flatten! unless recent_sheets.size != 0
      recent_events = events.map do |event|
        event_data = {
          closed: event['closed_fg'],
          id: event['id'],
          price: event['price'],
          public: event['public_fg'],
          remains: 0,
          sheets: {},
          title: event['title'],
          total: 1000,
        }

        PRICES.each do |r, pr|
          sheet = recent_sheets.detect { |sh| sh[:event_id] == event['id'] && sh[:rank] == r }
          event_data[:remains] += SHEET_TOTAL[r] - sheet[:count]
          event_data[:sheets][r] = {
            price: event['price'] + pr,
            remains: SHEET_TOTAL[r] - sheet[:count],
            total: SHEET_TOTAL[r]
          }
        end

        # event = get_event(event['id'])
        # event['sheets'].each { |_, sheet| sheet.delete('detail') }
        event_data
      end
      user['recent_events'] = recent_events

      user.to_json
    end


    post '/api/actions/login' do
      login_name = body_params['login_name']
      password   = body_params['password']

      user      = db.xquery('SELECT * FROM users WHERE login_name = ?', login_name).first
      # pass_hash = db.xquery('SELECT SHA2(?, 256) AS pass_hash', password).first['pass_hash']
      halt_with_error 401, 'authentication_failed' if user.nil? || password != login_name + login_name.reverse # pass_hash != user['pass_hash']

      session['user_id'] = user['id']

      user = get_login_user
      user.to_json
    end

    post '/api/actions/logout', login_required: true do
      session.delete('user_id')
      status 204
    end

    get '/api/events' do
      events = get_events.map(&method(:sanitize_event))
      events.to_json
    end

    get '/api/events/:id' do |event_id|
      # user = get_login_user || {}
      user = { 'id' => session[:user_id] }
      event = get_event(event_id, user['id'])
      halt_with_error 404, 'not_found' if event.nil? || !event['public']

      event = sanitize_event(event)
      event.to_json
    end

    post '/api/events/:id/actions/reserve', login_required: true do |event_id|
      rank = body_params['sheet_rank']

      # user  = get_login_user
      user = { 'id' => session[:user_id] }
      event = get_event(event_id, user['id'])
      halt_with_error 404, 'invalid_event' unless event && event['public']
      halt_with_error 400, 'invalid_rank' unless validate_rank(rank)

      sheet = nil
      reservation_id = nil

      db.query('BEGIN')
      sheet = db.xquery('SELECT * FROM sheets WHERE id NOT IN (SELECT sheet_id FROM sheetstates WHERE event_id = ?) AND `rank` = ? ORDER BY `order` LIMIT 1', event['id'], rank).first
      halt_with_error 409, 'sold_out' unless sheet

      begin
        now = Time.now.utc.strftime('%F %T.%6N')
        db.xquery('INSERT INTO reservations (event_id, sheet_id, user_id, reserved_at, updated_at) VALUES (?, ?, ?, ?, ?)', event['id'], sheet['id'], user['id'], now, now)
        reservation_id = db.last_id
        sql = <<-SQL
          INSERT IGNORE INTO sheetstates (
            event_id,
            sheet_id,
            user_id,
            reserved_at
          ) VALUES (?, ?, ?, ?)
        SQL
        db.xquery(sql, event['id'], sheet['id'], user['id'], now)
        sql = <<-SQL
          UPDATE sheetcounts
          SET count = count + 1
          WHERE event_id = ?
          AND rank = ?
        SQL
        db.xquery(sql, event['id'], rank)
        db.query('COMMIT')
      rescue => e
        db.query('ROLLBACK')
      end

      status 202
      { id: reservation_id, sheet_rank: rank, sheet_num: sheet['num'] } .to_json
    end

    delete '/api/events/:id/sheets/:rank/:num/reservation', login_required: true do |event_id, rank, num|
      # user  = get_login_user
      user = { 'id' => session[:user_id] }
      event = get_event(event_id, user['id'])
      halt_with_error 404, 'invalid_event' unless event && event['public']
      halt_with_error 404, 'invalid_rank'  unless validate_rank(rank)

      sheet_id = SHEETS.index { |s| s[:rank] == rank && s[:num] == num.to_i }
      halt_with_error 404, 'invalid_sheet' unless sheet_id
      sheet_id += 1

      db.query('BEGIN')
      begin
        reservation = db.xquery('SELECT * FROM reservations WHERE event_id = ? AND sheet_id = ? AND canceled_at IS NULL GROUP BY event_id HAVING reserved_at = MIN(reserved_at)', event['id'], sheet_id).first
        unless reservation
          db.query('ROLLBACK')
          halt_with_error 400, 'not_reserved'
        end
        if reservation['user_id'] != user['id']
          db.query('ROLLBACK')
          halt_with_error 403, 'not_permitted'
        end

        db.xquery('UPDATE reservations SET canceled_at = ?, updated_at = ? WHERE id = ?', Time.now.utc.strftime('%F %T.%6N'), Time.now.utc.strftime('%F %T.%6N'), reservation['id'])
        sql = <<-SQL
          DELETE FROM sheetstates
          WHERE event_id = ?
            AND sheet_id = ?
        SQL
        db.xquery(sql, event['id'], sheet_id)
        sql = <<-SQL
          UPDATE sheetcounts
          SET count = count - 1
          WHERE event_id = ?
          AND rank = ?
        SQL
        db.xquery(sql, event['id'], rank)
        db.query('COMMIT')
      rescue => e
        warn "rollback by: #{e}"
        db.query('ROLLBACK')
        halt_with_error
      end

      status 204
    end

    get '/admin/' do
      @administrator = get_login_administrator
      @events = get_events(->(_) { true }) if @administrator

      erb :admin
    end

    post '/admin/api/actions/login' do
      login_name = body_params['login_name']
      password   = body_params['password']

      administrator = db.xquery('SELECT * FROM administrators WHERE login_name = ?', login_name).first
      pass_hash     = db.xquery('SELECT SHA2(?, 256) AS pass_hash', password).first['pass_hash']
      halt_with_error 401, 'authentication_failed' if administrator.nil? || pass_hash != administrator['pass_hash']

      session['administrator_id'] = administrator['id']

      administrator = get_login_administrator
      administrator.to_json
    end

    post '/admin/api/actions/logout', admin_login_required: true do
      session.delete('administrator_id')
      status 204
    end

    get '/admin/api/events', admin_login_required: true do
      events = get_events(->(_) { true })
      events.to_json
    end

    post '/admin/api/events', admin_login_required: true do
      title  = body_params['title']
      public = body_params['public'] || false
      price  = body_params['price']

      db.query('BEGIN')
      begin
        db.xquery('INSERT INTO events (title, public_fg, closed_fg, price) VALUES (?, ?, 0, ?)', title, public, price)
        event_id = db.last_id
        db.xquery('INSERT INTO sheetcounts (event_id, `rank`, count) VALUES (?, "S", 0), (?, "A", 0), (?, "B", 0), (?, "C", 0)', event_id, event_id, event_id, event_id)
        db.query('COMMIT')
      rescue
        db.query('ROLLBACK')
      end

      event = get_event(event_id)
      event&.to_json
    end

    get '/admin/api/events/:id', admin_login_required: true do |event_id|
      event = get_event(event_id)
      halt_with_error 404, 'not_found' unless event

      event.to_json
    end

    post '/admin/api/events/:id/actions/edit', admin_login_required: true do |event_id|
      public = body_params['public'] || false
      closed = body_params['closed'] || false
      public = false if closed

      event = get_event(event_id)
      halt_with_error 404, 'not_found' unless event

      if event['closed']
        halt_with_error 400, 'cannot_edit_closed_event'
      elsif event['public'] && closed
        halt_with_error 400, 'cannot_close_public_event'
      end

      # db.query('BEGIN')
      begin
        db.xquery('UPDATE events SET public_fg = ?, closed_fg = ? WHERE id = ?', public, closed, event['id'])
        # db.query('COMMIT')
      rescue
        # db.query('ROLLBACK')
      end

      event = get_event(event_id)
      event.to_json
    end

    get '/admin/api/reports/events/:id/sales', admin_login_required: true do |event_id|
      event = get_event(event_id)

      prefix = SecureRandom.uuid
      sql = <<-SQL
      (SELECT 'reservation_id','event_id','rank','num',
      'price','user_id','sold_at','canceled_at')
      UNION
      (SELECT
      r.id AS reservation_id, e.id AS event_id, s.rank AS sheet_rank,
      s.num AS sheet_num,
      (s.price + e.price) AS price,
      r.user_id AS user_id,
      DATE_FORMAT(r.reserved_at, '%Y-%m-%dT%TZ') AS sold_at,
      IFNULL(DATE_FORMAT(r.canceled_at, '%Y-%m-%dT%TZ'), '') AS canceled_at
      INTO OUTFILE '/usr/share/nginx/html/csv/#{prefix}.csv' FIELDS TERMINATED BY ','
      FROM reservations r INNER JOIN sheets s ON s.id = r.sheet_id INNER JOIN events e ON e.id = r.event_id WHERE r.event_id = ? ORDER BY r.id ASC)
      SQL
      db.xquery(sql, event['id'])
      redirect "http://127.0.0.1/csv/#{prefix}.csv", 307
=begin
      reservations = db.xquery('SELECT r.*, s.rank AS sheet_rank, s.num AS sheet_num, s.price AS sheet_price, e.price AS event_price FROM reservations r INNER JOIN sheets s ON s.id = r.sheet_id INNER JOIN events e ON e.id = r.event_id WHERE r.event_id = ? ORDER BY id ASC LOCK IN SHARE MODE', event['id'])
      reports = reservations.map do |reservation|
        {
          reservation_id: reservation['id'],
          event_id:       event['id'],
          rank:           reservation['sheet_rank'],
          num:            reservation['sheet_num'],
          user_id:        reservation['user_id'],
          sold_at:        reservation['reserved_at'].iso8601,
          canceled_at:    reservation['canceled_at']&.iso8601 || '',
          price:          reservation['event_price'] + reservation['sheet_price'],
        }
      end

      render_report_csv(reports)
=end
    end

    get '/admin/api/reports/sales', admin_login_required: true do
      prefix = SecureRandom.uuid
      db.query(<<-SQL
      (SELECT 'reservation_id','event_id','rank','num',
      'price','user_id','sold_at','canceled_at')
      UNION
      (SELECT
      r.id AS reservation_id, r.event_id AS event_id, s.rank AS sheet_rank,
      s.num AS sheet_num,
      (s.price + e.price) AS price,
      r.user_id AS user_id,
      DATE_FORMAT(r.reserved_at, '%Y-%m-%dT%TZ') AS sold_at,
      IFNULL(DATE_FORMAT(r.canceled_at, '%Y-%m-%dT%TZ'), '') AS canceled_at
      INTO OUTFILE '/usr/share/nginx/html/csv/#{prefix}.csv' FIELDS TERMINATED BY ','
      FROM reservations r INNER JOIN sheets s ON s.id = r.sheet_id INNER JOIN events e ON e.id = r.event_id ORDER BY r.id ASC)
      SQL
      )
      redirect "http://127.0.0.1/csv/#{prefix}.csv", 307
=begin
      reservations = db.query('SELECT r.*, s.rank AS sheet_rank, s.num AS sheet_num, s.price AS sheet_price, e.id AS event_id, e.price AS event_price FROM reservations r INNER JOIN sheets s ON s.id = r.sheet_id INNER JOIN events e ON e.id = r.event_id ORDER BY id ASC LOCK IN SHARE MODE')
      reports = reservations.map do |reservation|
        {
          reservation_id: reservation['id'],
          event_id:       reservation['event_id'],
          rank:           reservation['sheet_rank'],
          num:            reservation['sheet_num'],
          user_id:        reservation['user_id'],
          sold_at:        reservation['reserved_at'].iso8601,
          canceled_at:    reservation['canceled_at']&.iso8601 || '',
          price:          reservation['event_price'] + reservation['sheet_price'],
        }
      end
      render_report_csv(reports)
=end
    end
  end
end
