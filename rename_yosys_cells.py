#!/usr/bin/env python3

#
# OpenLane2 custom flow script to rename Yosys generated DFF instance names 
# so they match their 'Q' output net names.
#
# Copyright (c) 2024 Ken Pettit <pettitkd@gmail.com>
# SPDX-License-Identifier: Apache-2.0
#

import os
import re
import os.path
from pathlib import Path
from typing import List, Tuple

from openlane.steps import Step, ViewsUpdate, MetricsUpdate
from openlane.state import State

class RenameYosysCells(Step):

   id = "TT.Top.RenameYosysCells"
   name = "Rename Yosys Cells"
   inputs = []
   outputs = []

   def writeInst(self, o, l, instLines):
      # Get the cell name and instance name
      parts = instLines[0].split()
      cellName = parts[0]
      instName = parts[1]

      # Search the instLines for a Q, X or Y output
      for i in instLines:
         # NOTE:  Changing non-DFF instance names generates hundreds
         #        of warnings during STA about "pin not found".  It 
         #        is maybe useful to do if needed and you simply want
         #        to ignore the STA warnings.

         # Find the output of ANY instance
         #if '.Q(' in i or '.Y(' in i or '.X(' in i:

         # Find the output of DFF instances only
         if '.Q(' in i:
            # Get the net name of the cell output
            netName = i.split('(')[1].split(')')[0].strip()

            # Skip cells with default net names in their output
            if netName[0] == '_' and netName[-1] == '_':
               continue

            # Ensure the instance name is default
            if instName[0] != '_' or instName[-1] != '_':
               continue

            # Check for vector 
            if netName[-1] == ']':
               # Find the opening bracket
               x = netName.rfind('[')

               # Get the net basename
               baseName = netName[:x]
               
               # Get the vector number
               idx = int(netName[x+1:-1])

               # Build a new instance name
               if '.Q(' in i:
                  netName = baseName + f'_reg_{idx}'
               else:
                  netName = baseName + f'_{idx}'
            else:
               # For flops, add "_reg" to the instance name
               if '.Q(' in i:
                  netName = netName + '_reg'

            # Remove leading '\'
            if netName[0] == '\\':
               netName = netName[1:]

            # Replace any brackets in the net name, like for Generated loops
            netName = netName.replace('[', '_').replace(']', '_').replace('#', '_')

            # Log our action
            print(f'Renaming {instName} to {netName}', file=l)
            print(f'Renaming {instName} to {netName}')

            # Replace line 0 with the new instance name
            instLines[0] = f'  {cellName} {netName} (\n'
            break

      # Print all lines to the output file
      for i in instLines:
         o.write(i)

   def run(self, state_in: State, **kwargs) -> Tuple[ViewsUpdate, MetricsUpdate]:
      # Get the YOSYS synth directory
      stepNo = int(os.path.basename(self.step_dir).split('-')[0])
      synthDir = os.path.join(os.path.dirname(self.step_dir), f'{stepNo-1:02d}-yosys-synthesis')

      # Find the netlist
      p = Path(synthDir)
      for f in p.glob('*.v'):
         # Rename to x.orig.v
         nl = Path(f)
         nlOrig = os.path.join(os.path.dirname(f), nl.stem +  '.orig.v')
         os.rename(nl, nlOrig)

         # Parse the original file
         o = open(f, 'w')
         i = open(nlOrig, 'r')
         logFile = os.path.join(self.step_dir, 'rename_yosys_inst.log')
         l = open(logFile, 'w')
         inInst = False
         instLines = []
         while True:
            # Read the next line
            line = i.readline()
            if not line:
               break

            # Test if we are in an instance
            if inInst:
               # Append all lines to the instane definition
               instLines.append(line)
               if ');' in line:
                  # Instance closing found
                  inInst = False 

                  # Write this instance to the output file, 
                  # substituting the instance name if needed.
                  self.writeInst(o, l, instLines)

            # Test for start of instance
            elif 'sky130' in line:
               instLines = []
               instLines.append(line)
               inInst = True

            # Just write this line to the output
            else:
               o.write(line)

         # Close the output, input and log files
         o.close()
         i.close()
         l.close()
      return {}, {}

