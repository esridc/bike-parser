require 'csv.rb'
require 'json'
require "net/http"
require "uri"
require 'pry'

$accidentData = ""
# Bicycle PDF parser
Accident = Struct.new(:complaint, :date, :time, :day, 
					  :street1, :street2, :quadrant, :onstreet, :lat, :lon, 
					  :type, :injured, :vehicles, :bicycles)
def buildAccidentList()
	for i in 2010..2013
		file_str = ""
		File.open("#{i}.txt", "r") do |f|
  			f.each_line do |line|
    			file_str += line
  			end
		end
		file_str.gsub("\n",'')
		CSV.open("accidents_#{i}.csv", "wb") do |csv|
			csv << ["Complain Number", "Date", "Time", "Day",
		"Main Street", "Second Street", "Quadrant", "On Street",
		"Latitude", "Longitude", "Type", "# Injured", 
		"# Vehicles", "# Bikes"]
			buildAccidentsForYear(i, file_str, csv)
		end
	end
	puts $accidentData
end

def buildAccidentsForYear(year, file_str, csv)
	complaints = file_str.scan(/\d{5,9}/m)
	rowsNoComplaint = file_str.split(/\d{5,9}/m)
	accidents = Array.new
	for complaint in complaints 
		accidents.push(Accident.new(complaint, "0", "0", ""))
	end
	puts rowsNoComplaint.size
	puts accidents.size
	buildAccidents(rowsNoComplaint[1..-1], accidents, year, csv)
end

def buildAccidents(rowsNoComplaint, accidents, year, csv)
	index = 0
	rowsNoDate = Array.new
	streetMatchs = 0
	secondStreetBlanks = 0
	for row in rowsNoComplaint
		row = row.gsub("\n", " ")
		accident = accidents.at(index)
		dateAndRest = row.split(/\/#{year}/)
		accident[:date] = findDate("#{dateAndRest.at(0)}")
		timeAndRest = dateAndRest.at(1).strip
		accident[:time] = timeAndRest.scan(/\d{4}/).at(0)
		dayAndRest = timeAndRest.split(/\d{4}/).at(1)
		accident[:day] = dayAndRest.scan(/[a-zA-Z]{3}/).at(0)
		streetsAndRest = dayAndRest.split(/#{accident[:day]}/).at(1)
		accident = buildLocationFields(accident, streetsAndRest)
		accidentNumbers = findAccidentNumbers(dayAndRest.split(accident[:onstreet]).at(1))
		accident[:injured] = accidentNumbers.at(0)
		accident[:vehicles] = accidentNumbers.at(1)
		accident[:bicycles] = accidentNumbers.at(2)
		if accident[:street1] != ""
			streetMatchs = streetMatchs + 1
		else
			puts accident
			break
		end
		if accident[:street2] == ""
			secondStreetBlanks = secondStreetBlanks + 1
		end
		writeToCSV(accident, csv)
		index = index + 1
	end
	$accidentData += " #{year} Accidents: #{accidents.size} \n"
end

def buildLocationFields(accident, streetsAndRest)
		accident[:quadrant] = findQuadrant(streetsAndRest)
		streetText = streetsAndRest.split(/#{accident[:quadrant]}/).at(0)
		streets = findStreets(streetText)
		accident[:street1] = streets.at(0)
		accident[:street2] = streets.at(1)
		accident[:onstreet] = findOnStreet(streetsAndRest)
		accident[:type] = findType(streetsAndRest.split(accident[:quadrant]).at(1)
							.split(accident[:onstreet]).at(0))
		coords = getLatLon(accident[:street1], accident[:street2])
		if coords != nil
			accident[:lat] = coords.at(0)
			accident[:lon] = coords.at(1)
		end
		return accident
end
def regsFor(exps, blank)
	regs = Array.new
	for exp in exps
		regs.push(/#{blank}#{exp}#{blank}/)
	end
	return regs
end

def streetRegs()
	return ["ST","AVE","RD","PL","CIR","BRIDGE","DR","ALY","TERR",/d{2,}/,"POLE"]
end

def findQuadrant(streetsAndRest)
	quadrants = regsFor(["NW", "NE", "SE", "SW", "BN"], /(\s|￼| )/)
	for quadrant in quadrants
		partitionedRow = streetsAndRest.partition(quadrant)
		if !partitionedRow.at(1).empty?
			return quadrant.to_s.scan(/[A-Z]{2}/).first
		end
	end
	return ""
end

def findStreets(streetText)
	if streetText.empty? || streetText == nil
		return streetText
	end
	currentStreet = ""
	streetEnds = streetRegs()
	streetsWords = streetText.split(/(\s|￼| )/)
	streets = Array.new
	for streetWord in streetsWords
		if streetWord.scan(/\w/).size > 0
			if !currentStreet.empty?
				currentStreet += " "
			end
			currentStreet += streetWord
			if streetEnds.include? streetWord
				streets.push(currentStreet)
				currentStreet = ""
			end
		end
	end
	return streets
end

def findOnStreet(streetAndRest)
	onStreets = ["Within 100ft", "At Intersect", "Not at Inter", "N/A"]
	for onStreet in onStreets
		if streetAndRest.partition(onStreet).at(1) != ""
			return onStreet
		end
	end
	return ""
end

# takes everything after "On Street"
def findAccidentNumbers(remainder)
	numbers = Array.new
	numbersStringArray = remainder.split(/(\s|￼| )/)
	for numbersString in numbersStringArray
		if numbersString.scan(/\d/).size > 0
			numbers.push(numbersString)
		end
	end
	return numbers
end

def findType(string)
	type = ""
	typeStringArray = string.split(/(\s|￼| )/)
	for typeString in typeStringArray
		if typeString.scan(/\w/).size > 0
			if !type.empty?
				type += " "
			end
			type += typeString
		end
	end
	return type
end

def findDate(string)
	date = ""
	dateStringArray = string.split(/(\s|￼| )/)
	for dateString in dateStringArray
		if dateString.scan(/(\d|\/)/).size > 0
			date += dateString
		end
	end
	return dateString
end

def getLatLon(firstStreet, secondStreet)
	url = buildGeocodeURL(firstStreet, secondStreet)
	if url == nil
		return
	end
	uri = URI.parse(url)
	http = Net::HTTP.new(uri.host, uri.port)
	begin
		response = http.request(Net::HTTP::Get.new(uri.request_uri))
	rescue
		puts $@
		puts $!
		return nil
	end
	begin
		json = JSON.parse(response.body)
	rescue
		nil
	end
	location = json["locations"].at(0)
	if location == nil
		return
	end
	coordinates = location["extent"]
	if coordinates == nil
		return
	end
	lat = coordinates["xmin"]
	lon = coordinates["ymin"]
	name = location["name"]
	return [lat, lon]
end

def buildGeocodeURL(firstStreet, secondStreet)
	baseURL = "http://geocode.arcgis.com/arcgis/rest/services/World/GeocodeServer/find?text="
	finalURL = baseURL
	if firstStreet == nil || secondStreet == nil || firstStreet.empty? || secondStreet.empty?
		return nil
	end
	for streetWord in firstStreet.split(/\s/)
		finalURL += "#{streetWord}+"
	end
	finalURL += "%26+"
	for streetWord in secondStreet.split(/\s/)
		finalURL += "#{streetWord}+"
	end
	finalURL +="washington+dc&f=pjson"
	puts finalURL
	return finalURL
end

def writeToCSV(accident, csv)
	csv << [accident[:complaint], accident[:date], accident[:time], accident[:day],
		accident[:street1], accident[:street2], accident[:quadrant], accident[:onstreet],
		accident[:lat], accident[:lon], accident[:type], accident[:injured], 
		accident[:vehicles], accident[:bicycles]]
end

buildAccidentList()

