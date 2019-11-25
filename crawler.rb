require "selenium-webdriver"
require "capybara"
require "capybara/dsl"
require "byebug"
require "nokogiri"
require "date"
require "active_support/core_ext"

chrome_bin = ENV.fetch("GOOGLE_CHROME_SHIM", nil)

chrome_opts = chrome_bin ? { binary: chrome_bin } : {}

Capybara.register_driver :selenium do |app|
  capabilities = {
    chromeOptions: {
      args: %w[
        headless disable-gpu disable-dev-shm-usage
        no-sandbox disable-popup-blocking disable-extensions
        --enable-features=NetworkService,NetworkServiceInProcess
      ]
    }.merge(chrome_opts)
  }

  Capybara::Selenium::Driver.new(
    app,
    browser: :chrome,
    desired_capabilities: Selenium::WebDriver::Remote::Capabilities.chrome(
      capabilities
    )
  )
end
Capybara.ignore_hidden_elements = true
Capybara.default_driver = :selenium
Capybara.app_host = 'https://booksy.com'

module BooksyCrawler
  class Scrape
    include Capybara::DSL
    def login_site
      visit('https://booksy.com/biz-app/en-pl/login')

      fill_in('email', :with => 'hello@kimuramedia.pl')
      fill_in('password', :with => 'md6k8j4juy')
      click_button('Sign In')

      find('label', text: 'Week').click
      puts page.all(:css, 'calendar__body').inspect
      # byebug
      page.body
    end
  end
end

t = BooksyCrawler::Scrape.new

output = File.open( "booksy.html","w" )
output << t.login_site
output.close


COLORS = {
	"-color-2": "red", "-color-4": "green",
	"-color-27": "yellow", "-color-30": "green"
}

MONTHS = {
	Jan: 1, Feb: 2, Mar: 3, Apr: 4, May: 5, Jun: 6,
	Jul: 7, Aug: 8, Sep: 9, Oct: 10, Nov: 11, Dec: 12
}

def doctor_name_picker(full_string, patient_name, count)
	required_str = full_string.select { |x| x.include?(patient_name) }.first
	
	required_str.slice!(patient_name)
	required_str.strip!
end

def time_parser(column, time)
	from = time.split[0].split(':').map(&:to_i)
	to = time.split[2].split(':').map(&:to_i)
	
	from_hr = from[0]
	from_min = from[1]
	
	to_hr = to[0] 
	to_min = to[1]
	"#{
		DateTime.new(
			column[:year].to_i, 
			MONTHS[column[:month].to_sym], 
			column[:date].to_i, 
			from_hr, 
			from_min
		).httpdate.to_time.strftime('%I:%M%p')
	} - #{
		DateTime.new(
			column[:year].to_i, 
			MONTHS[column[:month].to_sym], 
			column[:date].to_i, 
			to_hr, 
			to_min
		).httpdate.to_time.strftime('%I:%M%p')
	}".strip
end

class Scrape
	def find_bookings
		a = Nokogiri::HTML(File.open("booksy.html"))
		bookings = a.css("div.calendar__body div.calendar__overlay div.calendar__column")
		
		info = (1..7).map do |day| 
			a.css("div.calendar__header")
			.children[day]
			.text
			.split 
		end
		month = a.css("div.header__datepicker__title").text.split[1]
		year = a.css("div.header__datepicker__title").text.split.last
		appointments_this_week = a.css("div.upcoming-visits-2__stats span.counter").text.split[1].to_i
		docs_and_patients = a.css("ul.list-vertical li.list__item")
		.map do |dp| 
			dp.css("div.upcoming-visits-2__slot a div.grid div.grid__item")[1] 
		end.reject do |item| 
			item.nil? || item == '' 
		end.map(&:text)
	
		columns = info.map do |day|
			{
				day: day[0],
				date: day[1],
				month: month,
				year: year,
				bookings: day[2]
			}
		end

		each_book = []
		bookings.each_with_index do |booking, i|
			booking.css("div.calendar-booking").each do |book|
				book.css("div.calendar-booking__body").each do |final|
					each_book <<  {
						color: COLORS[(final.values[0]&.split&.grep(/color/)[0]).to_sym],
						datetime: time_parser(
							columns[i], final.children[0].text
						),
						patient_name: final.children[2].children[0].text,
						doctor_name: doctor_name_picker(
							docs_and_patients, 
							final.children[2].children[0].text,
							appointments_this_week
						)
					}
				end
			end
		end
		each_book
	end
end

s = Scrape.new
puts s.find_bookings

