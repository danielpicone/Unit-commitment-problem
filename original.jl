
# Solving the unit commitment problem
using CPLEX
using JuMP
using YAML
using DataFrames
using Gadfly
# First solve D_i
srand(100)

T = 48
demand = 40+10*rand(T)
# demand = 40*rand(T)
# μ = 100*ones(T)
μ = 60*(rand(T)-0.5)
generators = YAML.load(open("generators.yml"))

original = JuMP.Model(solver = CplexSolver(CPXPARAM_ScreenOutput = 1, CPXPARAM_Preprocessing_Dual=-1, CPXPARAM_MIP_Display = 4))

@variable(original, 1>=x[keys(generators), t=1:T]>=0)
@variable(original, y[keys(generators), t=1:T], Bin)
@variable(original, startup[keys(generators), t=1:T], Bin)
# @variable(original, 1>=y[keys(generators), t=1:T]>=0)

@objective(original, Min, sum(d["cost"] * d["capacity"] * x[gen, t] +d["startup"]*startup[gen,t] for (gen,d) in generators,t=1:T))

# Demand constraints
@constraint(original, demand_constraint[t=1:T], sum(d["capacity"]*x[gen,t] for (gen,d) in generators) == demand[t])

# Min gen constraints
@constraint(original, min_gen1[gen in keys(generators), t=1:T], generators[gen]["capacity"]*x[gen, t] >= generators[gen]["mingen"]*y[gen, t])
@constraint(original, min_gen2[gen in keys(generators), t=1:T], x[gen, t] <= y[gen, t])
# # Ramp rate constraints
@constraint(original, ramp_down[gen in keys(generators), t=1:T-1], generators[gen]["capacity"]*(x[gen, t] - x[gen, t+1]) <= generators[gen]["ramp"])
@constraint(original, ramp_up[gen in keys(generators), t=1:T-1], generators[gen]["capacity"]*(x[gen, t] - x[gen, t+1]) >= -generators[gen]["ramp"])
# Start up constraint
@constraint(original, start_up[gen in keys(generators), t=2:T], startup[gen,t]>=y[gen,t]-y[gen,t-1])

solve(original)

function create_variables_dict(generators)
    generation_vars = Dict()
    for gen in keys(generators)
        generation_vars[gen] = Dict("generation" => getvalue(x[gen,1:T]),
        "on" => getvalue(y[gen,1:T])
        )
    end
    return generation_vars
end

generation_vars = create_variables_dict(generators)

# Create the dataframe
function create_generation_df(generators)
    df = DataFrames.DataFrame(generator = String[], cost = Float64[], max_capacity = Float64[], interval = Float64[], generation = Float64[], demand = Float64[])
    for (gen, d) in generators
        for t=1:T
            push!(df, [gen d["cost"] d["capacity"] t d["capacity"]*generation_vars[gen]["generation"][t] demand[t]])
        end
    end
    return df
end

df = create_generation_df(generators)

df[:generation] = max.(df[:generation],0)

demand_df = DataFrames.DataFrame(interval = collect(1:T+1)-0.5, demand = [demand;demand[end]])
plot(df,
   layer(demand_df, x=:interval,y=:demand,Geom.step, Theme(default_color="black")),
   layer(sort!(df, rev=true),x=:interval,y=:generation,color=:generator,Geom.bar))
