# I den här filen kan ni stoppa all inputdata. 
# Läs in datan ni fått som ligger på Canvas genom att använda paketen CSV och DataFrames

using CSV, DataFrames

function read_input()
    println("\nReading Input Data...")
    folder = dirname(@__FILE__)

    #Sets
    REGION = [:DE, :SE, :DK]
    # PLANT = [:Wind,  :PV, :Gas, :Hydro] # Add all plants
    # PLANT = [:Wind,  :PV, :Gas, :Hydro, :Battery] # Add all plants
    # PLANT = [:Wind,  :PV, :Gas, :Hydro, :Battery, :Transmission] # Add all plants
    PLANT = [:Wind,  :PV, :Gas, :Hydro, :Battery, :Transmission, :Nuclear] # Add all plants
    HOUR = 1:8760

    #Parameters
    numregions = length(REGION)
    numhours = length(HOUR)

    timeseries = CSV.read("$folder\\TimeSeries.csv", DataFrame)
    wind_cf = AxisArray(ones(numregions, numhours), REGION, HOUR)
    pv_cf = AxisArray(ones(numregions, numhours), REGION, HOUR)
    load = AxisArray(zeros(numregions, numhours), REGION, HOUR)

    wind_avg = AxisArray(ones(numregions), REGION)
    pv_avg = AxisArray(ones(numregions), REGION)
    load_max = AxisArray(zeros(numregions), REGION)

    inflow=timeseries[:, "Hydro_inflow"]                                                       

    for r in REGION
        wind_cf[r, :]=timeseries[:, "Wind_"*"$r"]                                                        # 0-1, share of installed cap
        pv_cf[r, :]=timeseries[:, "PV_"*"$r"]                                                           
        load[r, :]=timeseries[:, "Load_"*"$r"]    
        wind_avg[r]=sum(timeseries[:, "Wind_"*"$r"])/length(HOUR)                                                        # 0-1, share of installed cap
        pv_avg[r]=sum(timeseries[:, "PV_"*"$r"])/length(HOUR)                                                           
        load_max[r]=maximum(timeseries[:, "Load_"*"$r"])    
    end

    print(wind_avg)
    print(pv_avg)
    print(load_max)

    myinf = 1e8
    maxcaptable = [                                                             # GW
        # PLANT         DE             SE              DK       
        :Wind           180            280             90       
        :PV             460            75              60      
        :Gas            myinf          myinf           myinf         
        :Hydro          0              14              0       
        :Battery        myinf          myinf           myinf 
        :Transmission   myinf          myinf           myinf 
        :Nuclear        myinf          myinf           myinf 
    ]

    maxcap = AxisArray(maxcaptable[:,2:end]'.*1000, REGION, PLANT) # MW


    discountrate=0.05

    ic = Dict(
        # PLANT     #Cost euro/MW
        :Wind           =>  1100000,
        :PV             =>  600000,
        :Gas            =>  550000,
        :Hydro          =>  0,
        :Battery        =>  150000,
        :Transmission   =>  2500000,
        :Nuclear        =>  7700000
    )

    rc = Dict(
        # PLANT     #Cost euro/MWh_elec
        :Wind           =>  0.1,
        :PV             =>  0.1,
        :Gas            =>  2 + 22/0.4,
        :Hydro          =>  0.1,
        :Battery        =>  0.1,
        :Transmission   =>  0,
        :Nuclear        =>  4 + 3.2/0.4
    )

    fc = [
        # PLANT     #Cost euro/MWh_fuel
        :Wind       0
        :PV         0
        :Gas        22
        :Hydro      0
    ]

    lt = Dict(
        # PLANT     #lifetime years
        :Wind           =>  25,
        :PV             =>  25,
        :Gas            =>  30,
        :Hydro          =>  80,
        :Battery        =>  10,
        :Transmission   =>  50,
        :Nuclear        =>  50
    )

        

    ac = Dict(
        # PLANT     #lifetime years
        :Wind   =>  ic[:Wind]*discountrate/(1-1/(1+discountrate)^lt[:Wind]),
        :PV     =>  ic[:PV]*discountrate/(1-1/(1+discountrate)^lt[:PV]),
        :Gas    =>  ic[:Gas]*discountrate/(1-1/(1+discountrate)^lt[:Gas]),
        :Hydro  =>  ic[:Hydro]*discountrate/(1-1/(1+discountrate)^lt[:Hydro]),
        :Battery  =>  ic[:Battery]*discountrate/(1-1/(1+discountrate)^lt[:Battery]),
        :Transmission  =>  ic[:Transmission]*discountrate/(1-1/(1+discountrate)^lt[:Transmission]),
        :Nuclear  =>  ic[:Nuclear]*discountrate/(1-1/(1+discountrate)^lt[:Nuclear])
    )



    return (; REGION, PLANT, HOUR, numregions, load, maxcap, ic, rc, fc, lt, ac, wind_cf, pv_cf, inflow)

end # read_input
