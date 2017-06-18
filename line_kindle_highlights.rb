# coding: utf-8
require 'capybara'
require 'capybara/dsl'
require 'capybara/poltergeist'
require 'selenium-webdriver'
require 'line/bot'
require 'json'
require 'socket'
require_relative 'user_info'

class LineKindleHighlights
  include Capybara::DSL

  SELENIUM = 0
  POLTERGEIST = 1

  JSON_FILE_NAME = 'highlights.json'
  CRAWL_PAGE_NUM = 2

  def initialize(driver)
    # capybaraの設定
    Capybara.app_host = 'https://kindle.amazon.co.jp'
    Capybara.default_max_wait_time = 5
    case driver
    when SELENIUM
      Capybara.current_driver = :selenium
      Capybara.javascript_driver = :selenium
      Capybara.register_driver :selenium do |app|
        Capybara::Selenium::Driver.new(app, :browser => :chrome)
      end
    when POLTERGEIST
      Capybara.current_driver = :poltergeist
      Capybara.javascript_driver = :poltergeist
      Capybara.register_driver :poltergeist do |app|
        # 最新のSeleniumではFirefoxが動作しない問題があるのでchromeを使う
        Capybara::Poltergeist::Driver.new(app, {:timeout => 120, js_errors: false})
      end
      page.driver.headers = {'User-Agent' => 'Mac Safari'}
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
    print "login..."
    login
    print "ok.\n"

    print "go to highlights..."
    go_to_highlights
    print "ok.\n"

    CRAWL_PAGE_NUM.times do
      all('.title').each do |element|
        p element.text
      end

      all('.highlight').each do |element|
        unless @highlights.include?(element.text)
          # 新しいハイライトをLINEに送信する
          push_highlight(element.text)
          @highlights << element.text 
        end
      end

      next_page
    end

    print "logout\n"

    #print JSON.pretty_generate(@highlights)

    print "save highlights..."
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

    # ログイン済みの場合は抜ける
    return unless page.title.include?('Welcome')

    click_link 'sign in'
    fill_in 'ap_email',
      :with => KINDLE_EMAIL
    fill_in 'password',
      :with => KINDLE_PASSWORD
    click_on 'signInSubmit'
  end

  # Your Hightlightsのページに遷移する
  # @note ログイン直後のページで使う
  def go_to_highlights
    click_link 'Your Highlights'
  end

  # 次のページに遷移
  # @note Your Hightlightsのページで使うことで次の本のハイライトページに遷移する
  def next_page
    visit(find_by_id('nextBookLink', visible: false)[:href])
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

gs = TCPServer.open(12345)
addr = gs.addr
addr.shift
printf("server is on %s\n", addr.join(":"))

crawler = LineKindleHighlights.new(LineKindleHighlights::POLTERGEIST)

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
