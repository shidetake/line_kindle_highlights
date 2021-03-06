# coding: utf-8
require 'capybara'
require 'capybara/dsl'
require 'capybara/poltergeist'
require 'selenium-webdriver'
require 'line/bot'
require 'json'
require 'socket'
require 'optparse'
require_relative 'user_info'

# KindleのハイライトをLINE通知する
class LineKindleHighlights
  include Capybara::DSL

  SELENIUM = 0
  HEADLESS_CHROME = 1

  JSON_FILE_NAME = 'highlights.json'.freeze
  BOOK_NUM = 3

  def initialize(driver)
    # capybaraの設定
    Capybara.app_host = 'https://read.amazon.co.jp/notebook'
    Capybara.default_max_wait_time = 5
    case driver
    when SELENIUM
      Capybara.current_driver = :selenium
      Capybara.javascript_driver = :selenium
      Capybara.register_driver :selenium do |app|
        Capybara::Selenium::Driver.new(app, browser: :chrome)
      end

    when HEADLESS_CHROME
      Capybara.current_driver = :selenium
      Capybara.javascript_driver = :selenium

      capabilities = Selenium::WebDriver::Remote::Capabilities.chrome(
        chromeOptions: { args: %w(headless disable-gpu) }
        # chromeOptions: { args: %w() }
      )

      Capybara.register_driver :selenium do |app|
        Capybara::Selenium::Driver.new(
          app,
          browser: :chrome,
          desired_capabilities: capabilities
        )
      end
    end

    # lineの設定
    @line = Line::Bot::Client.new do |config|
      config.channel_secret = LINE_CHANNEL_SECRET
      config.channel_token  = LINE_CHANNEL_TOKEN
    end
    @user_id = LINE_USER_ID

    # ハイライト管理設定
    @highlights = []
    restore_highlights
  end

  # ハイライトをウェブから取得してLINE送信する
  def scrape
    print 'login...'
    login
    print "ok.\n"

    sleep 10
    dump

    p all('.kp-notebook-library-each-book')

    all('.kp-notebook-library-each-book').each.with_index do |book, i|
      # 次の本に移動
      puts book.text
      book.click
      sleep 5

      all('.kp-notebook-highlight').each do |element|
        next if @highlights.include?(element.text)

        # 新しいハイライトをLINEに送信する
        push_highlight('> ' + element.text)
        @highlights << element.text
      end

      break if i == BOOK_NUM - 1
    end

    print "logout\n"

    # print JSON.pretty_generate(@highlights)

    print 'save highlights...'
    store_highlights
    print "ok.\n"
  end

  # ページの情報をダンプする
  # @note for debug
  def dump
    print page.body
  end

  private

  # Kindleのマイページにアクセスしログインする
  def login
    visit('')

    sleep 5

    # ログイン済みの場合は抜ける
    return if page.title.include?('メモとハイライト')

    fill_in 'ap_email', with: KINDLE_EMAIL
    fill_in 'password', with: KINDLE_PASSWORD
    click_on 'signInSubmit'
  end

  # 外部ファイルから既に取得しているハイライトを読み出す
  def restore_highlights
    return unless File.exist?(JSON_FILE_NAME)
    File.open(JSON_FILE_NAME, 'r') do |file|
      @highlights = JSON.load(file)
    end
  end

  # ハイライトをJSON形式にして外部ファイルに保存する
  def store_highlights
    File.open(JSON_FILE_NAME, 'w') do |file|
      JSON.dump(@highlights, file)
    end
  end

  # LINE送信
  # @param [String] 送信するテキスト
  def push_highlight(highlight)
    p highlight
    message = {
      type: 'text',
      text: highlight
    }

    @line.push_message(@user_id, message)
  end
end

params = ARGV.getopts('', 'debug')

if params['debug']
  #crawler = LineKindleHighlights.new(LineKindleHighlights::HEADLESS_CHROME)
  crawler = LineKindleHighlights.new(LineKindleHighlights::SELENIUM)
  begin
    crawler.scrape
    exit
  rescue
    print crawler.dump
    raise
  end
end

gs = TCPServer.open(12_345)
addr = gs.addr
addr.shift
printf("server is on %s\n", addr.join(':'))

crawler = LineKindleHighlights.new(LineKindleHighlights::HEADLESS_CHROME)
loop do
  s = gs.accept
  print(s, " is accepted\n")

  begin
    crawler.scrape
  rescue
    print crawler.dump
    raise
  end

  print(s, " is gone\n")
  s.close
end
