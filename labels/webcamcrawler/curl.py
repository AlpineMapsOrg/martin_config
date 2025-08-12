import pycurl
from io import BytesIO

class Curl:
	def __init__(self,
		useragent='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/60.0.3112.113 Safari/537.36',
		cookiefile='cookie.txt',
		acceptheader="text/json"):
		self.useragent = useragent
		self.cookiefile = cookiefile
		self.acceptheader = acceptheader

	def url_to_file(url):
		return url.replace("https://", "")	\
				.replace("http://", "")		\
				.replace("/", ".")			\
				.replace("\\", ".")			\
				.replace("www", "")


	def curlCall(self, url, data=None, callBack=None, saveFile=False, encoding = "UTF-8", abbortIfSaved=False):
		if(abbortIfSaved):
			import os
			filename = Curl.url_to_file(url)
			if(os.path.exists(filename)):
				return

		c = pycurl.Curl()
		c.setopt(pycurl.URL, url)
		c.setopt(pycurl.HTTPHEADER, ['Accept: '+self.acceptheader+', */*; q=0.01'])
		c.setopt(pycurl.USERAGENT, self.useragent)
		c.setopt(pycurl.COOKIEFILE, self.cookiefile)
		c.setopt(pycurl.COOKIEJAR, self.cookiefile)
		c.setopt(pycurl.HTTPHEADER,['X-Requested-With: XMLHttpRequest'])
		c.setopt(pycurl.NOSIGNAL, 1)
		c.setopt(pycurl.ENCODING, "none")

		if data != None:
			data = data.encode(encoding)
			c.setopt(pycurl.POST, 1)
			c.setopt(pycurl.POSTFIELDS, data)

		data = BytesIO()
		c.setopt(c.WRITEFUNCTION, data.write)

		try:
			c.perform()
		except pycurl.error as error:
			errno = error.args[0]
			errstr = error.args[1]
			print("error: " + str(errno) + " " + str(errstr))
			if errno in [6, 7]:
				pass

		c.close()

		if saveFile:
			filename = Curl.url_to_file(url)
			with open(filename, 'wb') as file:
				file.write(data.getvalue().decode(encoding))

			return filename

		if callBack != None:
			callBack(data.getvalue().decode(encoding))
		else:
			return data.getvalue().decode(encoding)
