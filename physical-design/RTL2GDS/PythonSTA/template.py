import os

current_dir = os.getcwd()
file_list = os.listdir(current_dir)
print(file_list)

# open the file you want

# extract the file content in a data structure

# analyze the data
# 1. How many paths have negative slack (violated path)?

# 2. What is the average depth(or number of gates) on paths with the least positive slack?
#   - Notice the difference between an instance name vs. a net name

### Advanced questions, please answer as much as you know without the use of the internet 

# 3. What is the frequency of this design running at? From the timing perspective is there room to push for higher performance?

# 4. The presented timing report is from the signoff stage of the design (after routing), what is the first thing you noticed that is wrong with this report?

# 5. How would you resolve problem 4? You should also reconsider problem 3 

# remember to close the file especially when you are writing to it
