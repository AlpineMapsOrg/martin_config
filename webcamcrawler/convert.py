#!/bin/python

import sys
import json

import time
import random

from curl import Curl


# external postgres webcam table layout
# {id, name, lat, long, url}

# separates list into smaller chunks
# https://stackoverflow.com/a/16935535
def chunks(list, n):
    n = max(1, n)
    return (list[i:i+n] for i in range(0, len(list), n))

def write_as_sql_insert(filename, inserts):
	output = '''
INSERT INTO "external_webcams" ("name","lat","long","url","altitude")
VALUES
'''
	with open(filename, 'w') as file:
		file.write(output + inserts + ";")

def panomax_parser(filename):
	# name
	# latitude
	# longitude
	
	# the panomax json file does not give us the individual urls for this we have to call 
	# https://api.panomax.com/1.0/instances/thumbnails/<id>
	# but we can concat ids using "," in order to give us more data per website call
	# calling the url with all >500 ids is too much we therefore chunk them into smaller lists of about 20 ids each

	# get data from json
	chunk_size = 20
	data = None
	output=""
	with open(filename, 'r') as f:
		data = json.load(f)

	# load all ids
	id_list = []
	for d in data["instances"]:
		cam = data["instances"][d]["cam"]

		if all(k in cam for k in ("id","name","latitude","longitude")):
			id_list.append(d)

	# chunk the ids
	lists = list(chunks(id_list, chunk_size))

	index = 0

	# call the url and get the individual panorama urls
	c = Curl()
	for l in lists:
		index +=1
		url = "https://api.panomax.com/1.0/instances/thumbnails/" + ",".join(l)
		cam_data = json.loads(c.curlCall(url))

		for i in range(l.__len__()):
			cam = data["instances"][l[i]]["cam"]
			output += "('{0}', {1}, {2}, '{3}'),\n".format(cam["name"], cam["latitude"], cam["longitude"], cam_data[i]["url"], -1)# -1 as default altitude

		# we dont want to overload the website and trigger ddos prevention methods
		time.sleep(7 + 5*random.random())
		print(str(index) +" / "+  str(lists.__len__()))

	write_as_sql_insert("out/panomax_output.sql", output[:-2])



def feratel_parser(filename):
	data = None
	output=""
	with open(filename, 'r') as f:
		data = json.load(f)

	# name
	# lat
	# lng
	# url

	for d in data:
		# only if all keys are present add the entry to the output (e.g. there are some without lat/long)
		if all(k in d for k in ("name", "lat", "lng", "url")):
			output += "('{0}', {1}, {2}, '{3}'),\n".format(d["name"], d["lat"], d["lng"], d["url"], -1)# -1 as default altitude

	write_as_sql_insert("out/feratel_output.sql", output[:-2])


def itwms_parser(filename):
	data = None
	output=""
	with open(filename, 'r') as f:
		data = json.load(f)

	for d in data["LiveCam"]:
		title = ""
		if("pageTitle" in d["@attributes"] and d["@attributes"]["pageTitle"] != ""):
			title = d["@attributes"]["pageTitle"]
		elif("geoPlacename" in d["@attributes"] and d["@attributes"]["geoPlacename"] != ""):
			title = d["@attributes"]["geoPlacename"]
		else:
			# if this error is shown look at the attributes and find a valid key/value and add an elif
			print("Error: No valid title found: ", d["@attributes"])
			continue

		url = ""
		if("url" in d["@attributes"]):
			url = d["@attributes"]["url"]
			if(not url.startswith("http")):# make sure that it starts with protocol
				url = "http://" + url
		else:
			# if this error is shown look at the attributes and find a valid key/value and add an elif
			# also consider d["Images"]
			# alternatively if no valid url is found skip it
			print("Error: No valid url found: ", d)
			continue

		latitude = ""
		if("geoLat" in d["@attributes"]):
			latitude = float(d["@attributes"]["geoLat"])
		else:
			# if this error is shown look at the attributes and find a valid key/value and add an elif
			print("Error: No valid latitude found: ", d["@attributes"])
			continue

		longitude = ""
		if("geoLong" in d["@attributes"]):
			longitude = float(d["@attributes"]["geoLong"])
		else:
			# if this error is shown look at the attributes and find a valid key/value and add an elif
			print("Error: No valid longitude found: ", d["@attributes"])
			continue

		altitude = ""
		if("geoAlt" in d["@attributes"]):
			altitude = int(float(d["@attributes"]["geoAlt"]))# some altitudes might have floating points -> convert first to float than to int
		else:
			altitude = -1 # default altitude
			# if this error is shown look at the attributes and find a valid key/value and add an elif
			# print("Error: No valid altitude found: ", d["@attributes"])
			# continue


		output += "('{0}', {1}, {2}, '{3}',{4}),\n".format(title,latitude,longitude,url,altitude)

	write_as_sql_insert("out/itwms_output.sql", output[:-2])

# usage: convert.py type file.json
# e.g. convert.py panomax panomaxweb_20240817.json
# or : convert.py feratel feratel_20240817.json
if __name__ == '__main__':
	if(sys.argv.__len__() <= 2):
		print("Error:")
		print("Usage: convert.py type file.json")
		exit()

	if(sys.argv[1] == "panomax"):
		panomax_parser(sys.argv[2])
	elif(sys.argv[1] == "feratel"):
		feratel_parser(sys.argv[2])
	elif(sys.argv[1] == "itwms"):
		itwms_parser(sys.argv[2])
	else:
		print("Error:")
		print("unknown type")


