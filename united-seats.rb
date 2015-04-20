require 'rubygems'
require 'headless'
require 'capybara'
require 'capybara/dsl'
require 'time'
require 'yaml'
require 'net/smtp'

Conf = YAML.load_file("config.yml")

if Conf[:use_headless]
  headless = Headless.new
  headless.start
end

Capybara.default_driver = :selenium
Capybara.default_wait_time = 30

class UnitedSeats
  include Capybara::DSL

  def find_seats
    log_in
    visit_and_block_text("https://www.united.com/web/en-US/apps/reservation/default.aspx",Conf[:record_locator])
    all('#tblCurrent tr').each do |tr|
      if tr.first(:xpath, ".//span[contains(text(),'#{Conf[:record_locator]}')]")
        seat_map_xpath = "//h1[@id='ctl00_ContentPageHeading_PageHeader1_h1PageHeading']//span[text()[contains(.,'Seat Map')]]"
        click_and_block_xpath(tr.find(:xpath, ".//a[contains(text(),'View/Change Seats')]"), seat_map_xpath)
        all(".segmentTab A").each do |seg|
          if seg.first(:xpath, ".//div[contains(text(),'#{Conf[:flight_number]}')]")
            active_flight_xpath = "//ul[@class='segmentTab']//li[@class='active']//div[text()[contains(.,'#{Conf[:flight_number]}')]]"
            click_and_block_xpath(seg, active_flight_xpath)
            check_seats
            exit
          end
        end
        break
      end
    end
  end

  def log_in
    visit("https://www.united.com/web/en-US/apps/account/account.aspx")
    fill_in 'ctl00_ContentInfo_SignIn_onepass_txtField', :with => Conf[:login]
    fill_in 'ctl00_ContentInfo_SignIn_password_txtPassword', :with => Conf[:password]
    click_button 'ctl00_ContentInfo_SignInSecure'
  end

  def check_seats
    econ_aisle_all = all('table.economy tr.asileseats td.available').size
    econ_window_all = all('table.economy tr.windowseats td.available').size
    econ_aisle_plus = all('table.economy tr.asileseats td.available.legroom').size
    econ_window_plus = all('table.economy tr.windowseats td.available.legroom').size
    econ_aisle_normal = econ_aisle_all - econ_aisle_plus
    econ_window_normal = econ_window_all - econ_window_plus

    aisle_available = (Conf[:econplus_seats] ? econ_aisle_plus : 0) + (Conf[:normal_seats] ? econ_aisle_normal : 0)
    window_available = (Conf[:econplus_seats] ? econ_window_plus : 0) + (Conf[:normal_seats] ? econ_window_normal : 0)

    if aisle_available > 0 || window_available > 0
      send_email(Conf[:notify_address],"Non-middle seats available for #{Conf[:record_locator]} flight #{Conf[:flight_number]} (a:#{aisle_available},w:#{window_available})")
    elsif Conf[:send_not_found]
      send_email(Conf[:not_found_address],"Non-middle seats not found for #{Conf[:record_locator]} flight #{Conf[:flight_number]}")
    end
  end

  def send_email(to,message)
    msg = <<END_OF_MESSAGE
From: #{Conf[:from_address]}
To: #{to}
Date: #{Time.now.rfc2822}

#{message}
END_OF_MESSAGE

    Net::SMTP.start(Conf[:smtp_server]) do |smtp|
      smtp.send_message msg, Conf[:from_address], to
    end
  end

  def visit_and_block_text(url,text)
    visit(url)
    has_content?(text)
  end

  def click_and_block_xpath(node,xpath)
    node.click
    find(:xpath, xpath)
  end
end

UnitedSeats.new.find_seats
