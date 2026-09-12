#!/bin/bash
source /home/carsten/my_python/bin/activate
/home/carsten/my_python/bin/python /home/carsten/git/trading_tool/aktienchecker/get_lastdates.py --ticker "^GDAXI"
/home/carsten/my_python/bin/python /home/carsten/git/trading_tool/aktienchecker/get_lastdates.py --ticker "^GSPC"
/home/carsten/my_python/bin/python /home/carsten/git/trading_tool/aktienchecker/get_lastdates.py --ticker "^NDX"
/home/carsten/my_python/bin/python /home/carsten/git/trading_tool/aktienchecker/get_lastdates.py --ticker "^990100-USD-STRD"
/home/carsten/my_python/bin/python /home/carsten/git/trading_tool/aktienchecker/get_lastdates.py --ticker "^VIX"
/home/carsten/my_python/bin/python /home/carsten/git/trading_tool/aktienchecker/get_lastdates.py --ticker "^N225"
/home/carsten/my_python/bin/python /home/carsten/git/trading_tool/aktienchecker/get_lastdates.py --ticker "^RUT"
/home/carsten/my_python/bin/python /home/carsten/git/trading_tool/aktienchecker/get_lastdates.py --ticker "^STOXX"
/home/carsten/my_python/bin/python /home/carsten/git/trading_tool/aktienchecker/get_lastdates.py --ticker "EEM"
/home/carsten/my_python/bin/python /home/carsten/git/trading_tool/aktienchecker/get_lastdates.py --ticker "AAXJ"

