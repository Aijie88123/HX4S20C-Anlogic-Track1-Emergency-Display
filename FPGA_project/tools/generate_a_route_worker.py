from pathlib import Path
R=Path(__file__).resolve().parents[1]
s=(R/'common/distributed_map.v').read_text()
solver=s[s.index('module campus_route_solver('):s.index('endmodule')+len('endmodule')]
worker=s[s.index('module distributed_map_worker #('):s.index('// Atomic network->video transfer.')]
solver=solver.replace('module campus_route_solver(', 'module a_campus_route_solver(')
solver=solver.replace('reg [15:0] distance[0:12]', 'reg [4:0] distance[0:12]')
solver=solver.replace('reg [15:0] blocked,best_cost;', 'reg [15:0] blocked;reg [4:0] best_cost;')
old_cost="wire [15:0] proposed=distance[current]+((edge_index<12)?16'd176:16'd80);"
assert solver.count(old_cost)==1,'Graph weights changed: re-evaluate the fixed-graph encoding before generating RTL'
solver=solver.replace(old_cost, "wire [4:0] proposed=distance[current]+((edge_index<12)?5'd2:5'd1);")
solver=solver.replace('65535','31').replace("16'hffff","5'h1f").replace("(scan==root)?16'd0", "(scan==root)?5'd0")
assert '176' not in solver and '80' not in solver
worker=worker.replace('module distributed_map_worker #(', 'module a_distributed_map_worker #(').replace('campus_route_solver u_solver(', 'a_campus_route_solver u_solver(')
header='''`timescale 1ns/1ps
// A-specific exact distance encoding for this fixed campus graph.
// Every non-exit path contains n equal 176-unit road edges; a terminal exit
// adds one 80-unit spur. Costs n*176 and n*176+80 have the same strict order
// and ties as 2*n and 2*n+1. Exits are degree-one terminal nodes, never expanded.
// At most 12 edges precede termination, so all finite codes fit below INF=31.
// Dijkstra node/edge scan order, parents, routes and walking logic are retained.
// Generated from common/distributed_map.v; the legacy module remains unchanged.
'''
(R/'A_display/rtl/a_map_route_worker.v').write_text(header+solver+'\n\n'+worker)
print('Generated A fixed-graph exact 5-bit Dijkstra distance and walking worker')
