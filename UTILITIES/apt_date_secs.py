from astropy.time import Time, TimeCxcSec

"""
  https://docs.astropy.org/en/stable/time/

  secs      Seconds since 1998-01-01T00:00:00 (TT)
  date      YYYY:DDD:hh:mm:ss.ss..

    These functions are very thin wrappers around the Astropy Time
    function.  The purpose is mainly to reduce typing and the 
    possibility of typos. Basically they are convenience functions.

    Since the Time.now() function exists in Astropy Time, the
    capability is included here.

"""

# Input in Chandra seconds; Output in DOY date string
def date(intime=None):
    # If the user did not input a value for intime,
    # the user wants the present time in DOY string format
    if intime is None:
        this_date = Time.now().yday
    else:
        this_date = Time(intime, format='cxcsec', scale='utc').yday         
    return this_date

# Input in DOY date string; Output in Chandra seconds
def secs(intime = None):
    # If the user did not input a value for intime,
    # the user wants the present time in Chandra Seconds
    if intime is None:
        this_time= Time.now().cxcsec
    else:
        this_time = Time(intime, format='yday', scale='utc').cxcsec
    return this_time











        
