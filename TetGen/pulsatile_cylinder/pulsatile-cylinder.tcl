#
#   Copyright (c) 2009-2012 Open Source Medical Software Corporation
#   All rights reserved.  
#
#  This script requires the following files:
#     solver.inp
#  and should be sourced interactively from SimVascular
#

set use_ascii_format 0

source ../../common/executable_names.tcl

# sometimes creating the bct.dat.vtp might cause problems
#global guiABC
#set guiABC(create_vtp_file) 0

# sometimes scaling the flow can cause problems
#set guiABC(preserve_flow_by_scaling) 0

# having lots of problems with the line intersection with
# the edge boundary to calcuate the ratio map, so hack it here
source geom_createRatioMap.tcl

# let's use tetgen and polydata solids!
global gOptions 
set gOptions(meshing_kernel) TetGen
set gOptions(meshing_solid_kernel) PolyData
solid_setKernel -name PolyData

#
# prompt user for number of procs
#

set num_procs [tk_dialog .askthem "Select Number of Processors" "Number of Processors \n to use?" question 0 1 2 3 4]
incr num_procs

#
# prompt user for linear solver
#

set selected_LS [tk_dialog .askthem "Select Linear Solver" "Use which linear solver?" question 0 "  svLS  " " leslib "]

set rundir [clock format [clock seconds] -format "%m-%d-%Y-%H%M%S"]
set fullrundir [file join [pwd] $rundir]
file mkdir $fullrundir

if {$num_procs == 1} {
  set fullsimdir $fullrundir
} else {
  set fullsimdir [file join $fullrundir $num_procs-procs_case]
}

#
# prompt user for mesh type
#

set pulsatile_mesh_option [tk_dialog .askthem "Select the Mesh to Use" "Select the desired mesh" question 0 "  Isotropic Mesh  " "  Boundary Layer Mesh  "]
incr pulsatile_mesh_option

# sometimes we have to invert the normal to the inflow surface
global guiABC
if {$pulsatile_mesh_option == 1} {
  set guiABC(invert_face_normal) 0
} else {
  set guiABC(invert_face_normal) 0
}


# create model, mesh, and bc files
source pulsatile-create_model_and_mesh.tcl
demo_create_model $fullrundir
demo_create_mesh $fullrundir $pulsatile_mesh_option
demo_create_bc_files $fullrundir

#
#  Create script file for presolver
#
foreach i [mymesh Print] {
  set [lindex $i 0] [lindex $i 1]
}

puts "Create script file for presolver."
set fp [open [file join $fullrundir cylinder.svpre] w]
if {$use_ascii_format > 0} {
  puts $fp "ascii_format"
}
puts $fp "verbose"
puts $fp "mesh_and_adjncy_vtu [file join $fullrundir mesh-complete cylinder.mesh.vtu]"
puts $fp "prescribed_velocities_vtp [file join $fullrundir mesh-complete mesh-surfaces inflow.vtp]"
puts $fp "noslip_vtp [file join $fullrundir mesh-complete mesh-surfaces wall.vtp]"
puts $fp "zero_pressure_vtp [file join $fullrundir mesh-complete mesh-surfaces outlet.vtp]"
puts $fp "set_surface_id_vtp [file join $fullrundir mesh-complete cylinder.exterior.vtp] 1"
puts $fp "write_geombc [file join $fullrundir geombc.dat.1]"
puts $fp "write_restart [file join $fullrundir restart.0.1]"
close $fp

#
#  Call pre-processor
#
puts "Run cvpresolver."
catch {exec $PRESOLVER [file join $fullrundir cylinder.svpre]} msg
puts $msg

#
# prompt user for the number of timesteps
#

set timesteps [tk_dialog .askthem "Select the Number of Time Steps" "Select the Number of Time Steps" question 0 "  16  " "  32  " "  64  " " 128  " " 256  " " 512  "]
set timesteps [expr pow(2,$timesteps) * 16]

puts "timesteps: $timesteps"
if {[expr int(fmod($timesteps,16))] > 0} {
  return -code error "ERROR in number of specified timesteps"
}

set total_timesteps [expr 2*$timesteps]

#
#  Run solver.
#

puts "Run Solver."

#
#  more files needed by solver
#

file copy [file join $fullrundir bct.dat.inflow] [file join $fullrundir bct.dat]
set fp [open [file join $fullrundir numstart.dat] w]
fconfigure $fp -translation lf
puts $fp "0"
close $fp

set infp [open solver.inp r]

set outfp [open $fullrundir/solver.inp w]
fconfigure $outfp -translation lf

if {$use_ascii_format == 0} {
   set file_format binary
} else {
   set file_format ascii
}

while {[gets $infp line] >= 0} {
  regsub -all my_initial_time_increment $line [expr 0.2/$timesteps] line
  regsub -all my_number_of_time_steps $line $total_timesteps line
  regsub -all my_output_format $line $file_format line
  if {$selected_LS} {
       regsub -all "\#leslib_linear_solver" $line {} line
  } else {
       regsub -all "\#svls_linear_solver" $line {} line
  }
  puts $outfp $line
}
close $infp
close $outfp

global tcl_platform
if {$tcl_platform(platform) == "windows"} {
  set npflag "-noprompt -localroot -localonly -user 1 -n"
} else {
  set npflag "-np"
}

proc handle { args } {
  puts -nonewline [ set [ lindex $args 0 ] ]
}

set fp [open [file join $fullrundir solver.log] w]
fconfigure $fp -translation lf
puts $fp "Start running solver..."
close $fp

set ::tail_solverlog {}
tail [file join \"$fullrundir"\ solver.log] .+ 1000 ::tail_solverlog
trace variable ::tail_solverlog w handle

eval exec \"$MPIEXEC\" -wdir \"$fullrundir\" $npflag $num_procs -env FLOWSOLVER_CONFIG \"$FLOWSOLVER_CONFIG\" \"$SOLVER\" >>& [file join $rundir solver.log] &

set endstep 0
while {$endstep < $total_timesteps} {
  set waittwoseconds 0
  after 2000 set waittwoseconds 1
  vwait waittwoseconds
  if {![file exists [file join $fullsimdir "numstart.dat"]]} continue
  set fp [open [file join $fullsimdir "numstart.dat"] r]
  gets $fp endstep
  close $fp
  set endstep [string trim $endstep]
}

cancelTail [file join \"$fullrundir"\ solver.log]

#
#  Create ParaView files
#
puts "Reduce restart files."
if {$use_ascii_format != 0} {
  set aflag "-nonbinary"
} else {
  set aflag ""
}

puts "exec $POSTSOLVER -indir $fullsimdir -outdir $fullsimdir -start 1 -stop $endstep -incr 1 -sim_units_mm -vtkcombo -vtu cylinder_results -vtp cylinder_results"

if [catch {exec $POSTSOLVER -indir $fullsimdir -outdir $fullrundir -start 1 -stop $endstep -incr 1 -sim_units_mm -vtkcombo -vtu cylinder_results.vtu -vtp cylinder_results.vtp} msg] {
   puts $msg
   return -code error "ERROR running postsolver!"
}
#  compare results
#

source pulsatile-compare_with_analytic.tcl

