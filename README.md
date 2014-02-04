Trineo Apex Utils
=================

A collection of useful Apex utility classes for the Force.com platform.
Written by the dev team at [Trineo Ltd](http://www.trineo.co.nz) for the Force.com developer community.


QueryUtil
---------

Extends the capability of standard SOQL queries in Salesforce.
Accepts query strings in format "Select * From ..." and dynamically replaces "*" with all fields for the sObject table being queried. Custom objects are also supported.

MergeUtil
---------

Merge one or more sObject records with a string that contains merge fields in format {!SOBJECT_NAME.FIELD_NAME}
*Note:* Requires the QueryUtil class.

RandomUtil
---------

Provides utility methods associated with randomising. At present, includes:
``` java
- getRandomInteger(Integer lower, Integer upper): get an integer n where lower <= n < upper
- shuffle(List<Object>): randomise the order of the provided list in-place (mutating the original list)
```