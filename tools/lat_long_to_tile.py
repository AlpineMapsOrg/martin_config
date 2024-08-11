import math
import sys

'''
This program uses one of the predetermined locations
and gives you the vector tile with the given zoom level
'''
def deg2num(lat_deg, lon_deg, zoom):
      lat_rad = math.radians(lat_deg)
      n = 2.0 ** zoom
      xtile = int((lon_deg + 180.0) / 360.0 * n)
      ytile = int((1.0 - math.asinh(math.tan(lat_rad)) / math.pi) / 2.0 * n)
      return (xtile, ytile)


def main(zoom):
      loc = deg2num(47.07454640014584, 12.693882599999998, zoom) # Großglockner
      # loc = deg2num(48.08257492980377, 16.286316690168128, zoom) # Mödling (city south of Vienna)
      # loc = deg2num(46.88524290018454, 10.867279, zoom) # Wildspitze

      # print(str(zoom) +"," + str(loc[0]) + "," + str(loc[1]))
      print("http://localhost:3000/peaks/" + str(zoom) +"/" + str(loc[0]) + "/" + str(loc[1]))

      # tile with peaks, cities and cottages (around Großglockner)
      # localhost:3000/peaks,cities,cottages/10/548/359


# usage: lat_long_to_tile.py <zoom>
#     e.g. lat_long_to_tile.py 12
# output: link to local vector tile with corresponding x/y/z coordinates
if __name__ == '__main__':
      if(len(sys.argv) >=2):
            main(int(sys.argv[1]))