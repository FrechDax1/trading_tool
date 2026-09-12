#!/bin/bash
    host="srv1211.hstgr.io"
    user="u903087946_Q4Y"
    password="9B*w*lB!n"
    database="u903087946_Q4Y" 


echo "describe table index_prices;" | mysql --host=$host --user=$user --password=$password --database=$database
