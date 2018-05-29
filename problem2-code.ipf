#pragma TextEncoding = "UTF-8"
#pragma rtGlobals=3		// Use modern global access method and strict wave access.

Structure Problem2Structure

	Wave time_p
	Wave time_r
	wave Temp_r
	wave sleep_ph_r
	Wave time_th
	wave Temp_th
	

	Variable offset
	Variable cycler_sleep_hours
	Variable hours_tolerance // allowed variation in sleep time before measurement is unviable
	Variable Warmup // time for ring to thermalize after started measuring/initially put on
	Variable Cooldown // time ring measures for after it is removed
	
	Wave night_start
	wave night_stop
	
	wave cleaned_time 
	wave cleaned_temperature
	wave cleaned_sleep_ph
	wave cleaned_length
	

	
EndStructure



//**************************

Function analyse_nights_ring()

STRUCT Problem2Structure s
	s.offset = 0 //timezone
	s.cycler_sleep_hours = 9 //user defined
	s.hours_tolerance = 2
	s.warmup = 0 //minutes
	s.cooldown = 0// minutes

Wave s.time_r = root:raw_data:Timestamp_ring
Wave s.temp_r = root:raw_data:Temp_ring
wave s.sleep_ph_r = root:raw_data:sleep_ph_ring
Wave s.time_th = root:raw_data:datestamp_thermometer
wave s.Temp_th = root:raw_data:Temp_thermometer
Wave s.time_p = root:raw_data:datestamp_period


	rescale_timestamps(s)
	Get_night_start_stop(s)
	
	Get_timestamp_length_night(s)
	
	reject_ring_fail(s)
	Get_night_start_stop(s)

	Get_mean_T_SlPh_night(s)
	
	wave s.cleaned_sleep_ph = mean_phase_night
	wave s.cleaned_time = time_night
	wave s.cleaned_length = length_night
	
	Wave s.cleaned_temperature = mean_temp_night
	Correllation_thermo_vs_clean(s,"raw mean nightly temerature : ",0)
	wave temp_clean_copy,temp_th_copy
	duplicate/o temp_clean_copy clean_mean_temp_ring1
	duplicate/o temp_th_copy temp_thermometer1

	wave s.cleaned_temperature = median_temp_night
	Correllation_thermo_vs_clean(s,"raw median nightly temerature : ",1)

	Get_sleeping_mean_T(s)
	wave s.cleaned_temperature = asleep_temp_night
	Correllation_thermo_vs_clean(s,"mean temerature of sleep phase < 4: ",1)

	
	Get_waking_Temp(s)
	wave s.cleaned_temperature = waking_temp_night
	Correllation_thermo_vs_clean(s,"mean temerature over 20 minutes before waking: ",1)

	Wave s.cleaned_temperature = mean_temp_night
	reject_wakefull_night(s)
	reject_long_short_night(s)
	Correllation_thermo_vs_clean(s,"mean nightly temerature wakefull long/short nights rejected: ",0)
	duplicate/o temp_clean_copy clean_mean_temp_ring2
	duplicate/o temp_th_copy temp_thermometer2
	killwaves/z temp_clean_copy,themp_th_copy

End

Function rescale_timestamps(S) //  to display timestamps in igor with correct absolute dates
STRUCT Problem2Structure &S


	make/d/o/n=(dimsize(s.time_th,0)) time_thermometer
	make/d/o/n=(dimsize(s.time_r,0)) time_ring
	make/d/o/n=(dimsize(s.time_p,0)) time_period
	SetScale d 0,0,"dat", time_thermometer,time_ring,time_period

	time_thermometer = s.time_th[p] + S.offset//imported with time relative to 01/01/1904 // can add offset to correct for timezone
	time_ring = s.time_r[p]+date2secs(1970,01,01) 
	time_period= s.time_p[p] + S.offset

	wave s.time_r = time_ring
	wave s.time_th = time_thermometer
	wave s.time_p = time_period
	
end

Function Get_night_start_stop(s)
STRUCT  problem2structure &s

variable delta_time = 0
variable i_start = 0
variable i_stop = 0
variable i = 1
	make/d/o/n=0 night_start,night_stop
night_start = 0
night_stop = 0
variable delta_threshold_s = 60*60*3
	Do
		delta_time = s.time_r[i]-s.time_r[i-1]
		
		if(delta_time>delta_threshold_s)
			i_stop = i-1
			insertpoints/M=0 dimsize(night_start,0),1, night_start,night_stop
			night_start[dimsize(night_start,0)-1]=i_start
			night_stop[dimsize(night_start,0)-1]=i_stop
			i_start = i
		endif
	
		i+=1
	
	While(i<dimsize(s.time_r,0))
	
	i_stop = dimsize(s.time_r,0)-1
	insertpoints/M=0 dimsize(night_start,0),1, night_start,night_stop
	night_start[dimsize(night_start,0)-1]=i_start
	night_stop[dimsize(night_start,0)-1]=i_stop
	
	wave s.night_start = night_start
	wave s.night_stop = night_stop
End

Function Get_timestamp_length_night(s)
STRUCT PROBLEM2STRUCTURE &s

	make/d/o/n=(dimsize(s.night_stop,0)) time_night,length_night
	SetScale d 0,0,"dat", time_night
	time_night = (s.time_r[s.night_stop[p]]-mod(s.time_r[s.night_stop[p]],60*60*24)) //gives UTC midnight
	length_night = (s.night_stop[p]-s.night_start[p])/60 // in hours since there is measurement every 60 seconds
duplicate/o time_night time_night_raw
duplicate/o length_night length_night_raw
End

Function Get_mean_T_SlPh_night(s)
STRUCT problem2structure &s

	variable num_nights = dimsize(s.night_stop,0)
	make/d/o/n=(num_nights) mean_temp_night,mean_phase_night,median_temp_night
	
	variable i = 0
	
	Do
		make/d/o/n=(s.night_stop[i]-s.cooldown-(s.night_start[i]+s.warmup)+1) temp_night_i,phase_night_i
		temp_night_i = s.temp_r[p+s.night_start[i]+s.warmup]
		mean_temp_night[i]=mean(temp_night_i)
		median_temp_night[i]=median(temp_night_i)

		phase_night_i = s.sleep_ph_r[p+s.night_start[i]+s.warmup]
		mean_phase_night[i]=mean(phase_night_i)

		i+=1
	While(i<num_nights)
	duplicate/o mean_temp_night mean_temp_night_raw
	duplicate/o mean_phase_night mean_phase_night_raw
killwaves/z temp_night_i,phase_night_i
End

Function reject_long_short_night(s)//reject a night (do not include in cleaned temperature data) 
STRUCT problem2structure &s

	variable num_nights = dimsize(s.cleaned_temperature,0)
	variable i = 0
	variable csh = s.cycler_sleep_hours
	variable ht = s.hours_tolerance
	//reject nights that are too long or too short
	Do
		if(s.cleaned_length[i]>(csh+ht)||s.cleaned_length[i]<(csh-ht))
			deletepoints i,1,s.cleaned_length,s.cleaned_temperature,s.cleaned_time,s.cleaned_sleep_ph
			i-=1
			num_nights-=1
		endif
		i+=1
	While(i<num_nights)

End

Function reject_wakefull_night(s)//reject a night (do not include in cleaned temperature data) 
STRUCT problem2structure &s

	variable num_nights = dimsize(s.cleaned_temperature,0)
	variable i = 0
	variable awake_test = 2.7
	//reject nights where mean sleep phase is above some threshold (not smart, but just to test)
	Do
		if(s.cleaned_sleep_ph[i]>awake_test)
			deletepoints i,1,s.cleaned_length,s.cleaned_temperature,s.cleaned_time,s.cleaned_sleep_ph
			i-=1
			num_nights-=1
		endif
		i+=1
	While(i<num_nights)

End

function Correllation_thermo_vs_clean(s,infostr,killcopy)
STRUCT problem2structure &s
variable killcopy
string infostr

	duplicate/o s.temp_th temp_th_copy
	duplicate/o s.time_th time_th_copy
	duplicate/o	s.cleaned_temperature temp_clean_copy
	duplicate/o	s.cleaned_time time_clean_copy

	//fwd sense
	downsample2(s.cleaned_time,s.time_th,temp_clean_copy)
	downsample2(s.cleaned_time,s.time_th,time_clean_copy)
	//back sense
	downsample2(s.time_th,s.cleaned_time,temp_th_copy)
	downsample2(s.time_th,s.cleaned_time,time_th_copy)


	StatsRankCorrelationTest/T=1/Q temp_clean_copy,temp_th_copy
	wave W_StatsRankCorrelationTest
	variable spearman_r = W_StatsRankCorrelationTest[4]
	variable criticalvalue = W_StatsRankCorrelationTest[5]
	
	
	if(spearman_r>criticalvalue)
			print infostr+" : Null Hypothesis rejected, Spearmans Correlation Coefficient for: "+nameofwave(s.cleaned_temperature)+" = "+num2str(spearman_r)
		else
			print infostr+" : Null Hypothesis cannot be rejected (spearman) for:"+nameofwave(s.cleaned_temperature)
	endif
	dowindow/k WMRankCorrelationTable
	killwaves/z W_StatsRankCorrelationTest	

	StatsLinearCorrelationTest/T=1/Q temp_clean_copy,temp_th_copy
	wave W_StatsLinearCorrelationTest
	 variable linear_r = W_StatsLinearCorrelationTest[4]
	variable t_value = W_StatsLinearCorrelationTest[5]
	variable t_critical = W_StatsLinearCorrelationTest[9]
	variable F_value = W_StatsLinearCorrelationTest[10]
	variable F_critical = W_StatsLinearCorrelationTest[11]
	
	if(t_value>t_critical&&F_value>f_critical)
			print infostr+" : Null Hypothesis rejected, Linear Correlation Coefficient for: "+nameofwave(s.cleaned_temperature)+" = "+num2str(linear_r)
		else
			print infostr+" : Null Hypothesis cannot be rejected (linear) for:" +nameofwave(s.cleaned_temperature)
	endif
	
	if(killcopy==1)
		killwaves/z temp_th_copy,temp_clean_copy
	endif
	dowindow/k WMLinearCorrelationTable 
	Killwaves/z W_StatsLinearCorrelationTest
End

function downsample2(time_more,time_less,temp_more)// downsamples cleaned waves  to match the available thermometer readings by rejecting nights with no thermometer reading
wave time_more,time_less,temp_more
variable more_num_nights = dimsize(time_more,0)
variable i = more_num_nights-1
variable j = 0

	do
		findvalue/V=(time_more[i])/T=0.0 time_less
		//point stored in v_value variable
		if(v_value==-1)
			deletepoints i,1,temp_more
			j+=1
		endif
		i-=1
	while(i>=0)
end

Function reject_ring_fail(s)
STRUCT problem2structure &s

	variable fail = 32.5//30.05
	variable i=0
	variable num_points = dimsize(s.temp_r,0)
	
	duplicate/o s.temp_r temp_ring_nofail
	duplicate/o s.time_r time_ring_nofail
	duplicate/o s.sleep_ph_r sleep_ph_ring_nofail
	
	variable j = 0
	Do
		
		if(temp_ring_nofail[i]<fail)
		deletepoints i,1,temp_ring_nofail,time_ring_nofail,sleep_ph_ring_nofail
				i-=1
				num_points-=1
				j+=1
		endif
	i+=1
	While(i<num_points)
	wave s.temp_r = temp_ring_nofail
	wave s.time_r = time_ring_nofail
	wave s.sleep_ph_r = sleep_ph_ring_nofail
End

Function Get_waking_Temp(s)
STRUCT problem2structure &s

Variable minutes = 60
	variable num_nights = dimsize(s.night_stop,0)

	make/d/o/n=(num_nights) waking_temp_night
	
	variable i = 0
	Do
		make/d/o/n=(minutes) temp_night_i
		temp_night_i = s.temp_r[p+s.night_stop[i]-minutes-s.cooldown]
		waking_temp_night[i]=mean(temp_night_i)
		i+=1
	While(i<num_nights)

killwaves/z temp_night_i,phase_night_i

End

Function Get_sleeping_mean_T(s)
STRUCT problem2structure &s

	variable num_nights = dimsize(s.night_stop,0)
	make/d/o/n=(num_nights) asleep_temp_night
	variable i = 0
	variable j = 0
	Do
		make/d/o/n=(s.night_stop[i]-s.cooldown-(s.night_start[i]+s.warmup)+1) temp_night_i,phase_night_i,time_i
		temp_night_i = s.temp_r[p+s.night_start[i]+s.warmup]
		phase_night_i = s.sleep_ph_r[p+s.night_start[i]+s.warmup]
time_i = s.time_r[p+s.night_start[i]+s.warmup]
		make/d/o/n=0 sleeping_night,time_sleeping
		SetScale d 0,0,"dat", time_i,time_sleeping

		j=0
		Do	
			
			if(phase_night_i[j]<4)
			insertpoints 0,1, sleeping_night,time_sleeping
			sleeping_night[0] = temp_night_i[j]
			time_sleeping[0] = time_i[j]

			endif
			j+=1
		While(j<dimsize(phase_night_i,0))
		
		asleep_temp_night[i]=mean(sleeping_night)

		i+=1
	While(i<num_nights)

End



variable num_nights = dimsize(s.night_stop,0)
	make/d/o/n=(num_nights) mean_temp_night,mean_phase_night,median_temp_night
	
	variable i = 0
	
	Do
		make/d/o/n=(s.night_stop[i]-s.cooldown-(s.night_start[i]+s.warmup)+1) temp_night_i,phase_night_i
		temp_night_i = s.temp_r[p+s.night_start[i]+s.warmup]
		mean_temp_night[i]=mean(temp_night_i)
		median_temp_night[i]=median(temp_night_i)

		phase_night_i = s.sleep_ph_r[p+s.night_start[i]+s.warmup]
		mean_phase_night[i]=mean(phase_night_i)

		i+=1
	While(i<num_nights)
	duplicate/o mean_temp_night mean_temp_night_raw
	duplicate/o mean_phase_night mean_phase_night_raw
killwaves/z temp_night_i,phase_night_i