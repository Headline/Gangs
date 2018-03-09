import os
import os.path

def get_clean_path(array):
	somestr = ""
	for x in range(0, len(array) - 1):
		somestr += array[x] + "/"
	return somestr

def do_version_replace(current):
	oldlist = 0;
	with open(current) as f:
		oldlist = f.readlines();

	for i, line in enumerate(oldlist):
		if "$$version$" in line:
			print("Replacing...")
			oldlist[i] = line.replace("$$version$", os.getenv('TRAVIS_BUILD_NUMBER', "XXX"))
		
	with open(current, 'w') as f:
		f.writelines(oldlist)
		
path = get_clean_path(os.path.realpath(__file__).split("\\"))

for dirpath, dirnames, filenames in os.walk(path):
	for filename in filenames:
		current = dirpath + "/" + filename
		if filename.endswith(".sp"):
			print("Versioning: " + current)
			do_version_replace(current)
