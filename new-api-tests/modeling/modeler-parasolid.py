'''Test check using Parasolid kernel.

   If the Parasolid plugin is installed then the interface to the
   Parasolid modeling kernel will be defined.
'''
import sv
import vtk
import sys

print("Solid modeling kernel names: {0:s}".format(str(sv.modeling.Kernel.names)))

## Create a modeler.
#
try:
    modeler = sv.modeling.Modeler(sv.modeling.Kernel.PARASOLID)
except sv.modeling.Error as err:
    print("Exception type: ", type(err))
    print("Error: ", err)
    sys.exit(1)

## Create a cylinder.
#
print("Create a cylinder ...") 
center = [0.0, 0.0, 0.0]
axis = [0.0, 0.0, 1.0]
radius = 1.5
length = 10.0
cyl = modeler.cylinder(center=center, axis=axis, radius=radius, length=length)

print("cyl type: " + str(type(cyl)))
cyl_polydata = cyl.get_polydata() 
print("Cylinder: num nodes: {0:d}".format(cyl_polydata.GetNumberOfPoints()))
print("Cylinder: num cells: {0:d}".format(cyl_polydata.GetNumberOfCells()))

