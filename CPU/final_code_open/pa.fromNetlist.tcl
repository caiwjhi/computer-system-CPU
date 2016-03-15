
# PlanAhead Launch Script for Post-Synthesis pin planning, created by Project Navigator

create_project -name cpu -dir "G:/VHDL/cpu/planAhead_run_2" -part xc3s1200efg320-4
set_property design_mode GateLvl [get_property srcset [current_run -impl]]
set_property edif_top_file "G:/VHDL/cpu/cpu.ngc" [ get_property srcset [ current_run ] ]
add_files -norecurse { {G:/VHDL/cpu} }
set_param project.pinAheadLayout  yes
set_property target_constrs_file "cpu.ucf" [current_fileset -constrset]
add_files [list {cpu.ucf}] -fileset [get_property constrset [current_run]]
link_design
