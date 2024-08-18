External Webcams

# Datasources

## Panomax

all available webcams from panomax are available under the link below in a json format
https://api.panomax.com/1.0/maps/panomaxweb

## Feratel

all available webcams from panomax are available under the link below in a json format
https://www.feratel.com/index.php?type=123457
Note: the data is encased in html tags and contains illegal line breaks:
- remove the html tags from the start and end of the document
- search for the linebreaks: \n in the document and replace them with nothing in order to remove them
- after this test if your document is a valid json file (e.g. using an online validator)


# Convert to SQL

by calling the convert.py script we can convert the json files into appropriate postgresql insert into queries. Note for panomax we still have to call the panomax website since some information (webcam urls) are still locked behind additional website requests. Those additional website calls are also already programmed into the convert.py file.

```usage: convert.py type file.json```