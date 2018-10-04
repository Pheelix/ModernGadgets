debug = true
data = {}

function Initialize() 

    latitude = SELF:GetOption('Latitude')
    longitude = SELF:GetOption('Longitude')
    mTime = SKIN:GetMeasure(SELF:GetOption('TimestampMeasure'))

    if not mTime then RmLog('Must define a timestamp measure', 'Error') end

end

-- if you wish to update the info on-demand via a !CommandMeasure, simply move this code to another function (e.g. 'GetSunMoonTimes()').
-- additionally, you may substitute the values obtained in Initialize() with your own function arguments if you do this.
function Update()
    
    -- setup timestamps
    local tDate = os.date("!*t", mTime:GetValue())   -- WINDOWS timestamp value
    tDate.year = tDate.year - (1970 - 1601)   -- convert Windows timestamp (0 = 1/1/1601) to Unix/Lua timestamp (0 = 1/1/1970)
    local timestamp = os.time(tDate)

    local mDate = tonumber(tostring(timestamp) .. '000')   -- millisecond date (timestamp with three extra zeroes)
    
    -- create 'zero-date', or timestamp at 0:00 on current day
    local zDateTbl = os.date('*t', os.time()) -- table with current time values
    local zDate = tonumber(tostring(os.time{ year = zDateTbl.year, month = zDateTbl.month, day = zDateTbl.day, hour = 0, min = 0, sec = 0 }) .. '000')

    local sunTimes = SunCalc.getTimes(mDate, latitude, longitude)
    local moonTimes = SunCalc.getMoonTimes(zDate, latitude, longitude)
    local sunPosition = SunCalc.getPosition(mDate, latitude, longitude)
    local moonPosition = SunCalc.getMoonPosition(mDate, latitude, longitude)
    local moonIllumination = SunCalc.getMoonIllumination(mDate, latitude, longitude)
    
    --[[
        VALUES TO PROVIDE:
        data:
            sunRise (time string)
            sunSet (time string)
            sunTime (time string)
            sunDialAngle (deg)
            moonRise (time string)
            moonSet (time string)
            moonTime (time string)
            moonDialAngle (deg)
            moonViewAngle (deg)
    ]]--

    data.sunrise = os.date('%H:%M', correctTimestamp(sunTimes.sunrise))
    data.sunset = os.date('%H:%M', correctTimestamp(sunTimes.sunset))
    data.suntime = os.date('%H:%M', correctTimestamp(sunTimes.sunset - sunTimes.sunrise))
    data.moonrise = os.date('%H:%M', correctTimestamp(moonTimes.rise))
    data.moonset = os.date('%H:%M', correctTimestamp(moonTimes.set))
    data.moontime = os.date('%H:%M', correctTimestamp(getDifference(moonTimes.set, moonTimes.rise)))
    PrintTable(data)

    -- debug
    -- RmLog('getTimes():')
    -- PrintTable(sunTimes)
    -- RmLog('getMoonTimes():')
    -- PrintTable(moonTimes)
    -- RmLog('getPosition():')
    -- PrintTable(sunPosition)
    -- RmLog('getMoonPosition():')
    -- PrintTable(moonPosition)
    -- RmLog('getMoonIllumination():')
    -- PrintTable(moonIllumination)
    

end

function getDifference(a1, a2)

    return a1

end

function GetData(key) return data[key] or '---' end

-- ----- Utilities -----

function correctTimestamp(timestamp) return tostring(timestamp):sub(1,10) end

function toDegrees(rad) return rad * 180 / math.pi end

-- function to make logging messages less cluttered
function RmLog(message, type)

    if type == nil then type = 'Debug' end
      
    if debug == true then
        SKIN:Bang("!Log", message, type)
    elseif type ~= 'Debug' then
        SKIN:Bang("!Log", message, type)
    end
      
end

printIndent = '     '

-- prints the entire contents of a table to the Rainmeter log
function PrintTable(table)
    for k,v in pairs(table) do
        if type(v) == 'table' then
            local pI = printIndent
            RmLog(printIndent .. tostring(k) .. ':')
            printIndent = printIndent .. '  '
            PrintTable(v)
            printIndent = pI
        else
            RmLog(printIndent .. tostring(k) .. ': ' .. tostring(v))
        end
    end
end

-- ------------------------------------------------------------------------------------------------------------------------
-- ------------------------------------------------------------------------------------------------------------------------
-- ------------------------------------------------------------------------------------------------------------------------

--[[
 (c) 2011-2015, Vladimir Agafonkin
 SunCalc is a JavaScript library for calculating sun/moon position and light phases.
 https://github.com/mourner/suncalc
]]--

-- shortcuts for easier to read formulas

PI   = math.pi
sin  = math.sin
cos  = math.cos
tan  = math.tan
asin = math.asin
atan = math.atan2
acos = math.acos
rad  = PI / 180

-- sun calculations are based on http://aa.quae.nl/en/reken/zonpositie.html formulas


-- date/time constants and conversions

dayMs = 1000 * 60 * 60 * 24
J1970 = 2440588
J2000 = 2451545

function toJulian(date)  return date / dayMs - 0.5 + J1970  end
function fromJulian(j)   return (j + 0.5 - J1970) * dayMs  end
function toDays(date)    return toJulian(date) - J2000  end


-- general calculations for position

e = rad * 23.4397 -- obliquity of the Earth 

function rightAscension(l, b)  return atan(sin(l) * cos(e) - tan(b) * sin(e), cos(l));  end
function declination(l, b)     return asin(sin(b) * cos(e) + cos(b) * sin(e) * sin(l));  end

function azimuth(H, phi, dec)   return atan(sin(H), cos(H) * sin(phi) - tan(dec) * cos(phi));  end
function altitude(H, phi, dec)  return asin(sin(phi) * sin(dec) + cos(phi) * cos(dec) * cos(H));  end

function siderealTime(d, lw)  return rad * (280.16 + 360.9856235 * d) - lw;  end

function astroRefraction(h)
    if (h < 0) then -- the following formula works for positive altitudes only. 
        h = 0 -- if h = -0.08901179 a div/0 would occur. 
    end

    -- formula 16.4 of "Astronomical Algorithms" 2nd edition by Jean Meeus (Willmann-Bell, Richmond) 1998. 
    -- 1.02 / tan(h + 10.26 / (h + 5.10)) h in degrees, result in arc minutes -> converted to rad: 
    return 0.0002967 / math.tan(h + 0.00312536 / (h + 0.08901179))

end

-- general sun calculations

function solarMeanAnomaly(d)  return rad * (357.5291 + 0.98560028 * d)  end

function eclipticLongitude(M)

    local C = rad * (1.9148 * sin(M) + 0.02 * sin(2 * M) + 0.0003 * sin(3 * M)) -- equation of center 
    local P = rad * 102.9372 -- perihelion of the Earth 

    return M + C + P + PI
end

function sunCoords(d)

    M = solarMeanAnomaly(d)
    L = eclipticLongitude(M)

    return {
        dec = declination(L, 0),
        ra = rightAscension(L, 0)
    }

end

SunCalc = {}

-- calculates sun position for a given date and latitude/longitude

SunCalc.getPosition = function (date, lat, lng)

    lw  = rad * -lng
    phi = rad * lat
    d   = toDays(date)
    c  = sunCoords(d)
    H  = siderealTime(d, lw) - c.ra

    return {
        azimuth = azimuth(H, phi, c.dec),
        altitude = altitude(H, phi, c.dec)
    }

end


-- sun times configuration (angle, morning name, evening name)

times = {
    {-0.833, 'sunrise',       'sunset'      },
    {  -0.3, 'sunriseEnd',    'sunsetStart' },
    {    -6, 'dawn',          'dusk'        },
    {   -12, 'nauticalDawn',  'nauticalDusk'},
    {   -18, 'nightEnd',      'night'       },
    {     6, 'goldenHourEnd', 'goldenHour'  }
}

-- adds a custom time to the times config

SunCalc.addTime = function (angle, riseName, setName)
    table.insert(times, {angle, riseName, setName})
end


-- calculations for sun times

J0 = 0.0009

function julianCycle(d, lw)  return math.round(d - J0 - lw / (2 * PI))  end

function approxTransit(Ht, lw, n)  return J0 + (Ht + lw) / (2 * PI) + n  end
function solarTransitJ(ds, M, L)   return J2000 + ds + 0.0053 * sin(M) - 0.0069 * sin(2 * L)  end

function hourAngle(h, phi, d)  return acos((sin(h) - sin(phi) * sin(d)) / (cos(phi) * cos(d)))  end

-- returns set time for the given sun altitude
function getSetJ(h, lw, phi, dec, n, M, L)

    w = hourAngle(h, phi, dec)
    a = approxTransit(w, lw, n)
    return solarTransitJ(a, M, L)

end


-- calculates sun times for a given date and latitude/longitude

SunCalc.getTimes = function (date, lat, lng)

    lw = rad * -lng
    phi = rad * lat

    d = toDays(date)
    n = julianCycle(d, lw)
    ds = approxTransit(0, lw, n)

    M = solarMeanAnomaly(ds)
    L = eclipticLongitude(M)
    dec = declination(L, 0)

    Jnoon = solarTransitJ(ds, M, L)

    i, len, time, Jset, Jrise = nil


    result = {
        solarNoon = fromJulian(Jnoon),
        nadir = fromJulian(Jnoon - 0.5)
    }

    for i = 1,table.length(times) do
        time = times[i]

        Jset = getSetJ(time[1] * rad, lw, phi, dec, n, M, L)
        Jrise = Jnoon - (Jset - Jnoon)

        result[time[2]] = fromJulian(Jrise)
        result[time[3]] = fromJulian(Jset)
    end

    return result

end


-- moon calculations, based on http://aa.quae.nl/en/reken/hemelpositie.html formulas

function moonCoords(d) -- geocentric ecliptic coordinates of the moon 

    L = rad * (218.316 + 13.176396 * d) -- ecliptic longitude 
    M = rad * (134.963 + 13.064993 * d) -- mean anomaly 
    F = rad * (93.272 + 13.229350 * d)  -- mean distance 

    l  = L + rad * 6.289 * sin(M) -- longitude 
    b  = rad * 5.128 * sin(F)    -- latitude 
    dt = 385001 - 20905 * cos(M)  -- distance to the moon in km 

    return {
        ra = rightAscension(l, b),
        dec = declination(l, b),
        dist = dt
    }

end

SunCalc.getMoonPosition = function (date, lat, lng)

    lw  = rad * -lng
    phi = rad * lat
    d   = toDays(date)

    c = moonCoords(d)
    H = siderealTime(d, lw) - c.ra
    h = altitude(H, phi, c.dec)
    -- formula 14.1 of "Astronomical Algorithms" 2nd edition by Jean Meeus (Willmann-Bell, Richmond) 1998. 
    pa = atan(sin(H), tan(phi) * cos(c.dec) - sin(c.dec) * cos(H))

    h = h + astroRefraction(h) -- altitude correction for refraction 

    return {
        azimuth = azimuth(H, phi, c.dec),
        altitude = h,
        distance = c.dist,
        parallacticAngle = pa
    }

end


-- calculations for illumination parameters of the moon,
-- based on http://idlastro.gsfc.nasa.gov/ftp/pro/astro/mphase.pro formulas and
-- Chapter 48 of "Astronomical Algorithms" 2nd edition by Jean Meeus (Willmann-Bell, Richmond) 1998.

SunCalc.getMoonIllumination = function (date)

    d = toDays(date)
    s = sunCoords(d)
    m = moonCoords(d)

    sdist = 149598000 -- distance from Earth to Sun in km 

    phi = acos(sin(s.dec) * sin(m.dec) + cos(s.dec) * cos(m.dec) * cos(s.ra - m.ra))
    inc = atan(sdist * sin(phi), m.dist - sdist * cos(phi))
    angle = atan(cos(s.dec) * sin(s.ra - m.ra), sin(s.dec) * cos(m.dec) - cos(s.dec) * sin(m.dec) * cos(s.ra - m.ra))

    return {
        fraction = (1 + cos(inc)) / 2,
        phase = 0.5 + 0.5 * inc * (angle < 0 and -1 or 1) / math.pi,
        angle = angle
    }

end


function hoursLater(date, h)
    return date + h * dayMs / 24
end

-- calculations for moon rise/set times are based on http://www.stargazing.net/kepler/moonrise.html article

SunCalc.getMoonTimes = function (date, lat, lng)

    t = date
    hc = 0.133 * rad
    h0 = SunCalc.getMoonPosition(t, lat, lng).altitude - hc
    h1, h2, rise, set, a, b, xe, ye, d, roots, x1, x2, dx = nil

    -- go in 2-hour chunks, each time seeing if a 3-point quadratic curve crosses zero (which means rise or set) 
    for i=1,24,2 do
        h1 = SunCalc.getMoonPosition(hoursLater(t, i), lat, lng).altitude - hc
        h2 = SunCalc.getMoonPosition(hoursLater(t, i + 1), lat, lng).altitude - hc

        a = (h0 + h2) / 2 - h1
        b = (h2 - h0) / 2
        xe = -b / (2 * a)
        ye = (a * xe + b) * xe + h1
        d = b * b - 4 * a * h1
        roots = 0

        if d >= 0 then
            dx = math.sqrt(d) / (math.abs(a) * 2)
            x1 = xe - dx
            x2 = xe + dx
            if math.abs(x1) <= 1 then roots = roots + 1 end
            if math.abs(x2) <= 1 then roots = roots + 1 end
            if x1 < -1 then x1 = x2 end
        end

        if roots == 1 then
            if h0 < 0 then rise = i + x1
            else set = i + x1 end

        elseif roots == 2 then
            rise = i + (ye < 0 and x2 or x1)
            set = i + (ye < 0 and x1 or x2)
        end

        if rise and set then break end

        h0 = h2
    end

    result = {}

    if rise then result.rise = hoursLater(t, rise) end
    if set then result.set = hoursLater(t, set) end

    if not rise and not set then result[ye > 0 and 'alwaysUp' or 'alwaysDown'] = true end

    return result

end

-- ---------- NOT PART OF THE ORIGINAL SCRIPT - HAD TO BE ADDED FOR THE SCRIPT TO WORK IN LUA ----------

function math.round(x)
    if x%2 ~= 0.5 then
        return math.floor(x+0.5)
    end
    return x-0.5
end

function table.length(T)
    local count = 0
    for _ in pairs(T) do count = count + 1 end
    return count
  end