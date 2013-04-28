/**
 * Merge one or more sObject records with a string that contains merge fields in format {!SOBJECT_NAME.FIELD_NAME}
 *
 * Requires the QueryUtil class.
 *
 * @author  Luke
 * @date    Apr 2013
 */
public with sharing class MergeUtil {
	public class MergeException extends Exception {}

	public static final Integer MAX_RECORDS = 10;

	/**
	 * This static method returns a merged string given a string with merge fields and one or more record Ids.
	 * @param  toMerge      Unmerged string that contains merge fields in format {!SOBJECT_NAME.FIELD_NAME}.
	 * @param  recordIds    Id list of the records that should be merged.
	 * @return              The merged string.
	 */
	public static String mergeRecords(String toMerge, List<ID> recordIds) {
		if(toMerge == null) {
			throw new MergeException('Unmerged input cannot be null');
		}

		String merged = toMerge; 

		if(recordIds.size() > MAX_RECORDS) {
			throw new MergeException('Maximum of ' + MAX_RECORDS + ' can be merged');
		}

		for(ID recordId : recordIds) {
			if(recordId != null) {
				merged = mergeSingleRecord(merged, recordId);
			} else {
				System.debug('Found null record Id');
			}
		}

		return merged;
	}

	/**
	 * This static method returns a merged string given a string with merge fields and a single record Id.
	 * @param  toMerge  Unmerged string that contains merge fields in format {!SOBJECT_NAME.FIELD_NAME}.
	 * @param  recordId Id of the record that should be merged.
	 * @return          The merged string.
	 */
	public static String mergeSingleRecord(String toMerge, ID recordId) {
		if(toMerge == null) {
			throw new MergeException('Unmerged input cannot be null');
		}

		String merged = toMerge;
		String typeName = recordId.getSObjectType().getDescribe().getName();
		String queryStr = 'Select * From ' + typeName + ' Where Id = \'' + recordId + '\'';
		List<SObject> sobjectList = QueryUtil.query(queryStr);
		if(sobjectList.size() != 1) {
			throw new MergeException('Record with Id \'' + recordId + '\' does not exist (sObject type is ' + typeName);
		}
		SObject record = sobjectList[0];

		Schema.SObjectType sobjectType = Schema.getGlobalDescribe().get(typeName);
		Map<String, Schema.SObjectField> fieldMap = sobjectType.getDescribe().fields.getMap();

		for(Schema.SObjectField f : fieldMap.values()) {
		Schema.DescribeFieldResult describeField = f.getDescribe();
		String fieldName = describeField.getName();
		Object fieldVal = record.get(fieldName);
		String strVal = null;

		// If this field is a Date/time, format it in EST:
		if(describeField.getType() == Schema.DisplayType.DateTime) {
		if(fieldVal != null) {
		Datetime dt = (Datetime)fieldVal;
		strVal = dt.format('yyyy-MM-dd HH:mm:ss', 'America/New_York');
		} else {
		strVal = '';
		}
		} else {
			strVal = fieldVal != null ? String.valueOf(fieldVal) : '';
		}

		// Merge field:
		merged = merged.replace('{!' + typeName + '.' + fieldName  + '}', strVal);
			String link = URL.getSalesforceBaseUrl().toExternalForm() + '/' + record.Id;
			merged = merged.replace('{!' + typeName + '.Link}', link);
		}
		return merged;
	}
}
