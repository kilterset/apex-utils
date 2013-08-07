/*
 * Static methods to extend standard SOQL query capabilities.
 *
 * @author: Luke & James
 * @date: Dec 2012
 */
public class QueryUtil {

    public Enum QueryType {OuterQuery,InnerQuery}

    public class QueryException extends Exception {}

    public static final String regexChunk_FieldNames_StarFormat = '\\s*\\*\\s*';
    public static final String regexChunk_FieldNames_DotNotation = '\\s*\\w+\\.\\w+\\s*';
    public static final String regexChunk_FieldNames_Regular = '\\s*\\w+\\s*';

    public static final String regex_regularOrStarOrDotField_NonCap ='(?:'+regexChunk_FieldNames_DotNotation+'|'+regexChunk_FieldNames_StarFormat+'|'+regexChunk_FieldNames_Regular+')';
    public static final String regex_regularOrStarOrDotField_Cap ='('+regexChunk_FieldNames_DotNotation+'|'+regexChunk_FieldNames_StarFormat+'|'+regexChunk_FieldNames_Regular+')';

    public static final String regexChunk_FieldNames_Composite_InnerQuery_NonCap = 
            regex_regularOrStarOrDotField_NonCap +
            '(?:,' +
                regex_regularOrStarOrDotField_NonCap +
            ')*';

    public static final String regex_InnerQuery_NonCap = ('(?i)select\\s+'+regexChunk_FieldNames_Composite_InnerQuery_NonCap+'\\s+from\\s+\\w+.*');
    public static final String regex_InnerQuery_Cap = ('(?i)select\\s+('+regexChunk_FieldNames_Composite_InnerQuery_NonCap+')\\s+from\\s+(\\w+)(.*)');

    public static final String regexChunk_FieldNames_RelationshipNest = ('\\s*\\(\\s*'+regex_InnerQuery_NonCap+'\\s*\\)\\s*');

    public static final String regex_relshipQueryOrStarOrDotField_NonCap ='(?:'+regexChunk_FieldNames_DotNotation+'|'+regexChunk_FieldNames_StarFormat+'|'+regexChunk_FieldNames_RelationshipNest+')';
    public static final String regex_relshipQueryOrStarOrDotField_Cap ='('+regexChunk_FieldNames_DotNotation+'|'+regexChunk_FieldNames_StarFormat+'|'+regexChunk_FieldNames_RelationshipNest+')';

    public static final String regexChunk_FieldNames_Composite_OuterQuery = 
            '(' +
                regex_relshipQueryOrStarOrDotField_NonCap +
                '(?:,' +
                    regex_relshipQueryOrStarOrDotField_NonCap +
                ')*' +
            ')';
    
    public static final String regex_OuterQuery = ('(?i)select\\s+' + regexChunk_FieldNames_Composite_OuterQuery + '\\s+from\\s+([^\\s]+)(.*)');

    private static Map<Schema.SObjectType,List<String>> FieldNameCache = new Map<Schema.SObjectType,List<String>>();

    private static Map<Schema.SObjectType, List<Schema.ChildRelationship>> ObjectRelationshipsCache = new Map<Schema.SObjectType, List<Schema.ChildRelationship>>();

    //For each cached object type, a map from its relationship names to their corresponding type 
    private static Map<Schema.SObjectType, Map<String,Schema.SObjectType>> ObjectRelationshipNamesToTypeCache = new Map<Schema.SObjectType, Map<String,Schema.SObjectType>>();


    /*
     * Return query results as list of sObjects. 
     * Transform query string if it is in format "Select * From ..."
     */
    public static List<sObject> query(String query) {
        List<sObject> result = new List<sObject>();

        // System.debug('About to transform query string: ' + query);
        String queryStr = getTransformedQueryStr(query);
        // System.debug('About to perform query: ' + queryStr);

        try{
            System.debug(queryStr);
            result = Database.query(queryStr);
            System.debug('Returning ' + result.size() + ' result(s)...');
        }
        catch(Exception e) {
            System.debug('ERROR IN QUERYUTIL: ' + e.getMessage());
        }

        return result;
    }

    /*
     * Given a query string, replace * with comma-delimited list of all fields. 
     * If not in format "Select * From..." just return the same string.
     */
    public static String getTransformedQueryStr(String query) {
        String result = '';
        
        //Matcher outerQueryMatcher = Pattern.compile(regex_OuterQuery).matcher(query.toLowerCase());
        Matcher outerQueryMatcher = Pattern.compile(regex_OuterQuery).matcher(query);
        System.debug('ARGBLARG: ' + query);
        if(outerQueryMatcher.matches() && outerQueryMatcher.groupCount() == 3) {
            //If the outer query matches, there are three groups
            //1: the fields we're querying (including any * queries, dot notation, or relationship queries)
            //2: the object we're querying against
            //3: anything after that (where clauses, limit clauses, etc)
            
            String fieldsRawString = outerQueryMatcher.group(1);
            String sObjectName = outerQueryMatcher.group(2).toLowerCase();
            String remainder = outerQueryMatcher.group(3);


            //First up, we'll get the star fields (caching stuff as we go). We'll get relationship info too
            Schema.SObjectType targetType = GlobalInfoCache.GlobalDescribeCache.get(sObjectName);
            if(targetType == null) {
                throw new QueryException('Could not execute Query, \'' + sObjectName + '\' is not a valid type to query against');
            }

            Schema.DescribeSObjectResult describe = GlobalInfoCache.retrieveDescribe(targetType);

            List<String> allFieldList = retrieveAllFieldList(targetType, describe);

            List<Schema.ChildRelationship>  childRelationships = retrieveAllChildRelationships(targetType, describe); 

            Map<String,Schema.SObjectType> relationshipNamesToType= retrieveRelationshipNamesToTypeNames(targetType);

            String allFields = String.join(allFieldList, ', ');

            //Star fields are now available in allFields
            

            //Now we're going to parse the fieldsRawString
            List<String> fieldRequests = parseFieldsRawString(fieldsRawString,QueryType.OuterQuery);



            //OK, so now we have a list of fields. Make sure we don't have any exact duplicates of any of them. This won't relationship query dups
            if(listContainsDups(fieldRequests)) {
                throw new QueryException('Error in Query. There was a duplicate in the list of fields asked for');
            }

            //Right, now that we have a list of fields, we'll go and do any substitutions we need to
            for(Integer index = 0; index < fieldRequests.size(); index++) {
                String field = fieldRequests[index];
                System.debug('FIELDCHECK: ' + field);
                if(field.trim().left(1).equals('(')) {
                    //Relationship Query, so we need to get stuff relevant to the relationship
                    Matcher innerQueryMatcher = Pattern.compile(regex_InnerQuery_Cap).matcher(field.substring(1,field.length()-1).trim()); //Remove brackets, trim
                    System.debug('CHECKING INNER QUERY');
                    System.debug(innerQueryMatcher.matches());
                    System.debug(innerQueryMatcher.groupCount());
                    if(innerQueryMatcher.matches() && innerQueryMatcher.groupCount() == 3) { 
                        System.debug('SEEMS TO MATCH, DOING HEAVY LIFTING');
                        //If the inner query matches, there are three groups
                        //1: the fields we're querying (including any * queries, dot notation, or regular fields)
                        //2: the object we're querying against
                        //3: anything after that (where clauses, limit clauses, etc)
                        
                        String innerFieldsRawString = innerQueryMatcher.group(1);
                        String innerSObjectName = innerQueryMatcher.group(2).toLowerCase();
                        String innerRemainder = innerQueryMatcher.group(3);

                        //For the inner sobjectname - this will be in the form of the relationship name on its parent, so we need to get
                        //   its actual sobject type by looking at the parent's relationship to it
                        System.debug(relationshipNamesToType);
                        Schema.SObjectType innerTargetType = relationshipNamesToType.get(innerSObjectName);
                        if(innerTargetType == null) {
                            throw new QueryException('Could not execute Query, \'' + innerSObjectName + '\' is not a valid relationship for ' + sObjectName);
                        }

                        //Relationship info isn't needed in inner queries
                        Schema.DescribeSObjectResult innerDescribe = GlobalInfoCache.retrieveDescribe(innerTargetType);

                        List<String> innerAllFieldList = retrieveAllFieldList(innerTargetType, innerDescribe);

                        String innerAllFields = String.join(innerAllFieldList, ', ');

                        //Star fields are now available in allFields

                        //Now we're going to parse the fieldsRawString
                        List<String> innerFieldRequests = parseFieldsRawString(innerFieldsRawString,QueryType.InnerQuery);

                        //OK, so now we have a list of fields, all tidy, trim, lowercase, and collapsed. Make sure we don't have any exact duplicates of any of them.
                        if(listContainsDups(innerFieldRequests)) {
                            throw new QueryException('Error in Query. There was a duplicate in the list of fields asked for');
                        }

                        //Right, now that we have a list of fields, we'll go and do any substitutions we need to
                        Boolean haveStar = false;
                        for(Integer innerIndex = 0; innerIndex < innerFieldRequests.size(); innerIndex++) {
                            String innerField = innerFieldRequests[innerIndex];

                            if(innerField.equalsIgnoreCase('*')) {
                                System.debug('INNER STAR FIELD: ' + innerAllFields);
                                innerFieldRequests[innerIndex] = innerAllFields;
                                haveStar = true;
                                //This is a star field
                            }
                            else if(innerField.contains('.')) {
                                //Dot notation field, leave as is as it's valid as is hopefully, unless you suck.
                            }
                            else {
                                //This is a regular field, leave it as is. But: if we have a star field, throw exception
                                if(haveStar) throw new QueryException('Inner query includes both a star field and a Regular field in the select list - this is not valid, as the star field already grabs all regular fields');
                            }
                        }

                        //Great. Finished transforming the inner query. Throw it back to the outer query
                        field = '(select ' + String.join(innerFieldRequests,', ') + ' from ' + innerSObjectName + ' ' + innerRemainder + ')';
                        System.debug('FILLED field: ' + field);
                    }

                    //Inner query has been transformed, replace the chunk
                    //System.debug('About to replace ' + fieldRequests[index] + ' with ' + field);
                    fieldRequests[index] = field;
                }
                else if(field.contains('.')) {
                    //Dot notation field, leave as is: it's valid as is hopefully, unless you're silly.
                }
                else {
                    fieldRequests[index] = allFields;
                    //This is a star field - the only other option in the outer query (regular fields are not allowed)
                }
            }

            result = 'select ' + String.join(fieldRequests,', ') + ' from ' + sObjectName + ' ' + remainder ; 

        } else {
            // System.debug('Either query string not in correct format or doesnt need transforming');
            result = query;
        }

        return result;
    }

    /**
     * [parseFieldsRawString description]. Note that this will trim and collapse to single space everything it receives
     * @param  fieldsRawString [description]
     * @param  theQueryType    [description]
     * @return                 [description]
     */
    public static List<String> parseFieldsRawString(String fieldsRawString, QueryType theQueryType) {
        String fieldMatchingRegex = (theQueryType == QueryType.OuterQuery ? regex_relshipQueryOrStarOrDotField_Cap : regex_regularOrStarOrDotField_Cap);

        String regex_fieldRawVerifier = ('\\s*'+fieldMatchingRegex+'(?:\\s*,\\s*'+fieldMatchingRegex+')*'); //Will only verify a rawFieldString format, not capture properly (only gets last in repeated group - stupid Java)
        String regex_fieldExtract_firstField = '\\s*'+fieldMatchingRegex+'\\s*.*';
        String regex_fieldExtract_fieldsAfterFirst = '\\s*,\\s*'+fieldMatchingRegex+'\\s*';

        List<String> fieldRequests = new List<String>();

        //Verify fieldsRawString format
        Matcher verifier = Pattern.compile(regex_fieldRawVerifier).matcher(fieldsRawString);
        if(verifier.matches()) {
            System.debug('Verifier matches');
        }
        else {
            throw new QueryException('Error in Query, list of fields to get in outer query is not valid (this may not necessarily be the issue, but note that '+
                ' in the outer query you cannot mix Regular fields with Star fields ( \'*\' ), dot fields (e.g. \'Relationship.ID\'), or relationship queries (e.g. \'(select ID from Relationship)\'. '+ 
                    'Note also that you cannot nest Relationship Queries inside existing Relationship queries) ');
        }

        //extract first field from fieldsRawString
        Matcher extractFirstField = Pattern.compile(regex_fieldExtract_firstField).matcher(fieldsRawString);
        if(extractFirstField.matches()) {
            fieldRequests.add(extractFirstField.group(1).trim().replaceAll('\\s+',' '));
        }
        else {
            throw new QueryException('Error in Query, no valid fields (as in [select FIELDS from object] entered in Query');
        }
        
        //extract subsequent fields from fieldsRawString
        Matcher extractSubsequentFields = Pattern.compile(regex_fieldExtract_fieldsAfterFirst).matcher(fieldsRawString);
        while(extractSubsequentFields.find()) {
            fieldRequests.add(extractSubsequentFields.group(1).trim().replaceAll('\\s+',' '));
        }

        return fieldRequests;
    }

    

    private static List<String> retrieveAllFieldList(SObjectType targetType, Schema.DescribeSObjectResult describe) {
        List<String> allFieldList = FieldNameCache.get(targetType);
        if(allFieldList == null) {
            FieldNameCache.put(targetType,new List<String>(describe.fields.getMap().keySet()));
            allFieldList = FieldNameCache.get(targetType);
        }
        return allFieldList;
    }

    private static List<Schema.ChildRelationship> retrieveAllChildRelationships(SObjectType targetType, Schema.DescribeSObjectResult describe) {
        List<Schema.ChildRelationship> childRelationships = ObjectRelationshipsCache.get(targetType);
        if(childRelationships == null) {
            ObjectRelationshipsCache.put(targetType,describe.getChildRelationships());
            childRelationships = ObjectRelationshipsCache.get(targetType);
        }
        return childRelationships;
    }

    //NB: this will lower-case-ify the relationship name
    private static Map<String,Schema.SObjectType> retrieveRelationshipNamesToTypeNames(SObjectType targetType){
        Map<String,Schema.SObjectType> relationshipNamesToTypeNames = ObjectRelationshipNamesToTypeCache.get(targetType);
        if(relationshipNamesToTypeNames == null) {
            List<Schema.ChildRelationship> childRelationships = ObjectRelationshipsCache.get(targetType);
            relationshipNamesToTypeNames = new Map<String,Schema.SObjectType>();
            for(Schema.ChildRelationship rel : childRelationships) {
                //It is possible for the relationship name to be null - but this only appears to be possible for some special built in stuff, like UserProfileFeed. Discard those silently
                if(rel.getRelationshipName() != null) {
                    relationshipNamesToTypeNames.put(rel.getRelationshipName().toLowerCase(),rel.getChildSObject());
                }
            }
        }
        return relationshipNamesToTypeNames;
    }

    private static Boolean listContainsDups(List<String> theList) {
        //Everything converted to lowercase first to fake case insensitivity
        List<String> theListClone = theList.clone();
        for(Integer index = 0; index < theList.size(); index++) {
            theListClone[index] = theListClone[index].toLowerCase();
        }

        Set<String> dupCheckSet = new Set<String>();
        dupCheckSet.addAll(theListClone);
        
        if(dupCheckSet.size() != theList.size()) {
            return true;
        }
        else {
            return false;
        }
    }
}