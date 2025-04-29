# I den här filen bygger ni modellen. Notera att det är skrivet som en modul, dvs ett paket. 
# Så när ni ska använda det, så skriver ni Using energisystemprojekt i er REPL, då får ni ut det ni
# exporterat. Se rad 9.

module energisystemprojekt


using JuMP, AxisArrays, Gurobi, UnPack, CSV#, Plots, StatsPlots

export runmodel

include("input_energisystemprojekt.jl")

function buildmodel(input)

    println("\nBuilding model...")
 
    @unpack REGION, PLANT, HOUR, numregions, load, maxcap, ic, rc, fc, lt, ac, wind_cf, pv_cf, inflow = input

    m = Model(Gurobi.Optimizer)

    @variables m begin

        Electricity[r in REGION, p in PLANT, h in HOUR]         >= 0        # MWh/h
        Capacity[r in REGION, p in PLANT]                       >= 0        # MW

        Systemcost[r in REGION]                                 >= 0
        ReservoirLevel[h in HOUR]                               >= 0         #MW
        
        Co2[r in REGION]                                        >= 0

        # avg_wind[r in REGION] >= 0
        # avg_pv[r in REGION] >= 0
        
        # Excercise 2
        # b
        Battery[r in REGION, h in HOUR]                         >= 0
        BatteryCharge[r in REGION, h in HOUR]                   >= 0

        ExcessElectricity[r in REGION, h in HOUR]               >= 0

        # Excercise 3
        Transmission[r1 in REGION, r2 in REGION, h in HOUR]     >= 0          # first region is sender second is reciever
        TransmissionCap[r1 in REGION, r2 in REGION]             >= 0          # first region is sender second is reciever

    end #variables


    #Variable bounds
    for r in REGION, p in PLANT
        set_upper_bound(Capacity[r, p], maxcap[r, p])
    end


    @constraints m begin
        # [r in REGION],
        #     avg_wind[r] == sum(wind_cf[r, :])/length(HOUR)

        # [r in REGION],
        #     avg_pv[r] == sum(pv_cf, :)/length(HOUR)


        GenerationGH[r in REGION, p in [:Gas, :Hydro], h in HOUR],
            Electricity[r, p, h] <= Capacity[r, p] # * capacity factor

        GenerationW[r in REGION, h in HOUR],
            Electricity[r, :Wind, h] <= Capacity[r, :Wind] * wind_cf[r, h]

        GenerationP[r in REGION, h in HOUR],
            Electricity[r, :PV, h] <= Capacity[r, :PV] * pv_cf[r, h]

        Load[r in REGION, h in HOUR],
            sum(Electricity[r, p, h] for p in PLANT) >= load[r,h]


        rescap[h in HOUR],
            ReservoirLevel[h] <= 33000000

        ReservoirLevel[1] == ReservoirLevel[length(HOUR)]

        resChange[h in 1:length(HOUR)-1],
            ReservoirLevel[h+1] == ReservoirLevel[h] + inflow[h]- Electricity[:SE, :Hydro, h]
        

        CO2[r in REGION],
            Co2[r] == sum(Electricity[r, :Gas, h]/0.4*0.202 for h in HOUR)

        
        SystemCost[r in REGION],
            Systemcost[r] >= 
                sum(ac[p]*Capacity[r, p] for p in PLANT) +
                sum(rc[p]*Electricity[r, p, h] for p in PLANT, h in HOUR) +
                sum(ac[:Transmission]/2*TransmissionCap[r,r2] for r2 in REGION)  # Excercise 3

        # Excercise 2
        # a

        # Model cant be solved with this req
        sum(Co2[r] for r in REGION) <= 0.5* 1.387744849926479e8

        # b
        BatteryCap[r in REGION, h in HOUR],
            Battery[r, h] <= Capacity[r, :Battery]

        GenerationB[r in REGION, h in HOUR],
            Electricity[r, :Battery, h] <= Battery[r, h]

        Excess[r in REGION, h in HOUR],
            ExcessElectricity[r, h] == sum(Electricity[r, p, h] for p in PLANT) - load[r,h]


        # UseExcess[r1 in REGION, h in HOUR],
        #     BatteryCharge[r1, h]/0.9 == ExcessElectricity[r1, h] # Remove for excercise 3

        Charge[r in REGION, h in 1:length(HOUR)-1],
            Battery[r, h+1] == Battery[r, h] - Electricity[r, :Battery, h] + BatteryCharge[r, h]


        # # Excercise 3
        MirrorTransmissionCap[r1 in REGION, r2 in REGION],
            TransmissionCap[r1, r2] == TransmissionCap[r2, r1]

        TransCap[r1 in REGION, r2 in REGION, h in HOUR],
            Transmission[r1, r2, h] <= TransmissionCap[r1, r2]

        UseExcess[r1 in REGION, h in HOUR],
            sum(Transmission[r1, r2, h] for r2 in REGION)/0.98 + BatteryCharge[r1, h]/0.9 == ExcessElectricity[r1, h]

        GenerationT[r2 in REGION, h in HOUR],
            Electricity[r2, :Transmission, h] == sum(Transmission[r1, r2, h] for r1 in REGION)


        # # Excercise 4
        GenerationN[r in REGION, h in HOUR],
            Electricity[r, :Nuclear, h] <= Capacity[r, :Nuclear]

    end #constraints

    # print("\n\n\n\n")
    # println(avg_wind)
    # println(avg_pv)
    # print("\n\n\n\n")

    @objective m Min begin
        sum(Systemcost[r] for r in REGION)
    end # objective

    return (;m, Capacity, Electricity, load, Co2, ReservoirLevel, TransmissionCap, Transmission)

end # buildmodel

function runmodel() 

    input = read_input()

    model = buildmodel(input)

    @unpack m, Capacity, Electricity, load, Co2, ReservoirLevel, TransmissionCap, Transmission = model   
    
    println("\nSolving model...")
    
    status = optimize!(m)
    

    if termination_status(m) == MOI.OPTIMAL
        println("\nSolve status: Optimal")   
    elseif termination_status(m) == MOI.TIME_LIMIT && has_values(m)
        println("\nSolve status: Reached the time-limit")
    else
        error("The model was not solved correctly.")
    end

    Cost_result = objective_value(m)/1000000 # M€
    Capacity_result = value.(Capacity)

    println("\ncapacity: ", Capacity_result)
    println("\ncapacity_transposed: ", transpose(Array(Capacity_result)))
    println("")
    # println("\nelectricity Jan: ", sum(Array(value.(Electricity[:,:, 147:651])), dims=3))
    # println("\nTotal load: ", sum(Array(value.(load[:, 147:651])), dims=2))
    println("")
    println("\ntotal electricity: ", sum(Array(value.(Electricity)[:, :, :]), dims=3))
    println("\ntotal wind: ", sum(Array(value.(Electricity)[:, :Wind, :]), dims=2))
    println("\ntotal solar: ", sum(Array(value.(Electricity)[:, :PV, :]), dims=2))
    println("\ntotal gas: ", sum(Array(value.(Electricity)[:, :Gas, :]), dims=2))
    println("\ntotal hydro: ", sum(Array(value.(Electricity)[:, :Hydro, :]), dims=2))
    println("\ntotal battery: ", sum(Array(value.(Electricity)[:, :Battery, :]), dims=2))
    println("\ntotal nuclear: ", sum(Array(value.(Electricity)[:, :Nuclear, :]), dims=2))
    println("\ntotal transmission: ", sum(Array(value.(Transmission)[:, :, :]), dims=3))
    println("")
    println("")
    println("\nReservoir level: ",value.(ReservoirLevel)[8760])
    println("\nCo2: ", sum(value.(Co2)))
    println("\nTransmissionCap: ", value.(TransmissionCap))
    println("\nCost (M€): ", Cost_result)
    # println("new")
   

    # println(value.(Electricity[:DE, :Wind, 147:651].data))
    # println(value.(Electricity[:DE, :PV, 147:651].data))
    # println(value.(Electricity[:DE, :Gas, 147:651].data))
    # println(value.(Electricity[:DE, :Hydro, 147:651].data))
    # println(Array(value.(load[:DE, 147:651])))

    # CSV.write("DE_JAN.csv", DataFrame(value.(Electricity[:DE, :Wind, 147:651].data)))

    

    nothing

end #runmodel



end # module

