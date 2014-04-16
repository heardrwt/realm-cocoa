/*************************************************************************
 *
 * TIGHTDB CONFIDENTIAL
 * __________________
 *
 *  [2011] - [2014] TightDB Inc
 *  All Rights Reserved.
 *
 * NOTICE:  All information contained herein is, and remains
 * the property of TightDB Incorporated and its suppliers,
 * if any.  The intellectual and technical concepts contained
 * herein are proprietary to TightDB Incorporated
 * and its suppliers and may be covered by U.S. and Foreign Patents,
 * patents in process, and are protected by trade secret or copyright law.
 * Dissemination of this information or reproduction of this material
 * is strictly forbidden unless prior written permission is obtained
 * from TightDB Incorporated.
 *
 **************************************************************************/

#import <Foundation/Foundation.h>

#include <tightdb/util/unique_ptr.hpp>
#include <tightdb/table.hpp>
#include <tightdb/descriptor.hpp>
#include <tightdb/table_view.hpp>
#include <tightdb/lang_bind_helper.hpp>

#import "RLMTable_noinst.h"
#import "RLMView_noinst.h"
#import "RLMQuery_noinst.h"
#import "RLMRow.h"
#import "RLMDescriptor_noinst.h"
#import "TDBColumnProxy.h"
#import "NSData+RLMGetBinaryData.h"
#import "PrivateTDB.h"
#import "RLMSmartContext_noinst.h"
#import "util_noinst.hpp"

using namespace std;


@implementation RLMTable
{
    tightdb::TableRef m_table;
    id m_parent;
    BOOL m_read_only;
    RLMRow * m_tmp_row;
}



-(instancetype)init
{
    self = [super init];
    if (self) {
        m_read_only = NO;
        m_table = tightdb::Table::create(); // FIXME: May throw
    }
    return self;
}

-(instancetype)initWithColumns:(NSArray *)columns
{
    self = [super init];
    if (!self)
        return nil;

    m_read_only = NO;
    m_table = tightdb::Table::create(); // FIXME: May throw

    if (!set_columns(m_table, columns)) {
        m_table.reset();

        // Parsing the schema failed
        //TODO: More detailed error msg in exception
        @throw [NSException exceptionWithName:@"tightdb:invalid_columns"
                                                         reason:@"The supplied list of columns was invalid"
                                                       userInfo:nil];
    }

    return self;
}

-(id)_initRaw
{
    self = [super init];
    return self;
}

-(BOOL)_checkType
{
    return YES;
    // Dummy - must be overridden in tightdb.h - Check if spec matches the macro definitions
}

-(RLMRow *)getRow
{
    return m_tmp_row = [[RLMRow alloc] initWithTable:self ndx:0];
}
-(void)clearRow
{
    // Dummy - must be overridden in tightdb.h

    // TODO: This method was never overridden in tightdh.h. Presumably above comment is made by Thomas.
    //       Clarify if we need the method.
}

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState*)state objects:(id __unsafe_unretained*)stackbuf count:(NSUInteger)len
{
    static_cast<void>(len);
    if(state->state == 0) {
        const unsigned long* ptr = static_cast<const unsigned long*>(objc_unretainedPointer(self));
        state->mutationsPtr = const_cast<unsigned long*>(ptr); // FIXME: This casting away of constness seems dangerous. Is it?
        RLMRow * tmp = [self getRow];
        *stackbuf = tmp;
    }
    if (state->state < self.rowCount) {
        [((RLMRow *)*stackbuf) TDB_setNdx:state->state];
        state->itemsPtr = stackbuf;
        state->state++;
    }
    else {
        *stackbuf = nil;
        state->itemsPtr = nil;
        state->mutationsPtr = nil;
        [self clearRow];
        return 0;
    }
    return 1;
}

-(tightdb::Table&)getNativeTable
{
    return *m_table;
}

-(void)setNativeTable:(tightdb::Table*)table
{
    m_table.reset(table);
}

-(void)setParent:(id)parent
{
    m_parent = parent;
}

-(void)setReadOnly:(BOOL)read_only
{
    m_read_only = read_only;
}

-(BOOL)isReadOnly
{
    return m_read_only;
}

-(BOOL)isEqual:(id)other
{
    if ([other isKindOfClass:[RLMTable class]])
        return *m_table == *(((RLMTable *)other)->m_table);
    return NO;
}

//
// This method will return NO if it encounters a memory allocation
// error (out of memory).
//
// The specified table class must be one that is declared by using
// one of the table macros TIGHTDB_TABLE_*.
//
// FIXME: Check that the specified class derives from RLMTable.
-(BOOL)hasSameDescriptorAs:(__unsafe_unretained Class)tableClass
{
    RLMTable * table = [[tableClass alloc] _initRaw];
    if (TIGHTDB_LIKELY(table)) {
        [table setNativeTable:m_table.get()];
        [table setParent:m_parent];
        [table setReadOnly:m_read_only];
        if ([table _checkType])
            return YES;
    }
    return NO;
}

//
// If the type of this table is not compatible with the specified
// table class, then this method returns nil. It also returns nil if
// it encounters a memory allocation error (out of memory).
//
// The specified table class must be one that is declared by using
// one of the table macros TIGHTDB_TABLE_*.
//
// FIXME: Check that the specified class derives from RLMTable.
-(id)castToTypedTableClass:(__unsafe_unretained Class)typedTableClass
{
    RLMTable * table = [[typedTableClass alloc] _initRaw];
    if (TIGHTDB_LIKELY(table)) {
        [table setNativeTable:m_table.get()];
        [table setParent:m_parent];
        [table setReadOnly:m_read_only];
        if (![table _checkType])
            return nil;
    }
    return table;
}

-(void)dealloc
{
    if ([m_parent isKindOfClass:[RLMSmartContext class]]) {
        RLMSmartContext *context = (RLMSmartContext *)m_parent;
        [context tableRefDidDie];
    }
}

-(NSUInteger)columnCount
{
    return m_table->get_column_count();
}

-(NSString*)nameOfColumnWithIndex:(NSUInteger)ndx
{
    return to_objc_string(m_table->get_column_name(ndx));
}

-(NSUInteger)indexOfColumnWithName:(NSString *)name
{
    return was_not_found(m_table->get_column_index(ObjcStringAccessor(name)));
}

-(RLMType)columnTypeOfColumnWithIndex:(NSUInteger)ndx
{
    return RLMType(m_table->get_column_type(ndx));
}

-(RLMDescriptor*)descriptor
{
    return [self descriptorWithError:nil];
}

-(RLMDescriptor*)descriptorWithError:(NSError* __autoreleasing*)error
{
    tightdb::DescriptorRef desc = m_table->get_descriptor();
    BOOL read_only = m_read_only || m_table->has_shared_type();
    return [RLMDescriptor descWithDesc:desc.get() readOnly:read_only error:error];
}

-(NSUInteger)rowCount // Implementing property accessor
{
    return m_table->size();
}

-(RLMRow *)insertEmptyRowAtIndex:(NSUInteger)ndx
{
    [self TDBInsertRow:ndx];
    return [[RLMRow alloc] initWithTable:self ndx:ndx];
}

-(BOOL)TDBInsertRow:(NSUInteger)ndx
{
    return [self TDBInsertRow:ndx error:nil];
}

-(BOOL)TDBInsertRow:(NSUInteger)ndx error:(NSError* __autoreleasing*)error
{
    if (m_read_only) {
        if (error)
            *error = make_tightdb_error(tdb_err_FailRdOnly, @"Tried to insert row while read-only.");
        return NO;
    }
    
    TIGHTDB_EXCEPTION_ERRHANDLER(m_table->insert_empty_row(ndx);, 0);
    return YES;
}


-(NSUInteger)TDB_addEmptyRow
{
    return [self TDB_addEmptyRows:1];
}

-(NSUInteger)TDB_addEmptyRows:(NSUInteger)num_rows
{
    // TODO: Use a macro or a function for error handling

    if(m_read_only) {
        @throw [NSException exceptionWithName:@"tightdb:table_is_read_only"
                                       reason:@"You tried to modify a table in read only mode"
                                     userInfo:nil];
    }

    NSUInteger index;
    try {
        index = m_table->add_empty_row(num_rows);
    }
    catch(std::exception& ex) {
        @throw [NSException exceptionWithName:@"tightdb:core_exception"
                                       reason:[NSString stringWithUTF8String:ex.what()]
                                     userInfo:nil];
    }

    return index;
}

-(RLMRow *)objectAtIndexedSubscript:(NSUInteger)ndx
{
    return [[RLMRow alloc] initWithTable:self ndx:ndx];
}

-(void)setObject:(id)newValue atIndexedSubscript:(NSUInteger)rowIndex
{
    tightdb::Table& table = *m_table;
    tightdb::ConstDescriptorRef desc = table.get_descriptor();

    if (table.size() < (size_t)rowIndex) {
        // FIXME: raise exception - out of bound
        return;
    }

    if ([newValue isKindOfClass:[NSArray class]]) {
        verify_row(*desc, (NSArray *)newValue);
        set_row(size_t(rowIndex), table, (NSArray *)newValue);
        return;
    }
    
    if ([newValue isKindOfClass:[NSDictionary class]]) {
        verify_row_with_labels(*desc, (NSDictionary *)newValue);
        set_row_with_labels(size_t(rowIndex), table, (NSDictionary *)newValue);
        return;
    }

    if ([newValue isKindOfClass:[NSObject class]]) {
        verify_row_from_object(*desc, (NSObject *)newValue);
        set_row_from_object(rowIndex, table, (NSObject *)newValue);
        return;
    }

    @throw [NSException exceptionWithName:@"tightdb:column_not_implemented"
                                   reason:@"You should either use nil, NSObject, NSDictionary, or NSArray"
                                 userInfo:nil];
}


-(RLMRow *)rowAtIndex:(NSUInteger)ndx
{
    // initWithTable checks for illegal index.

    return [[RLMRow alloc] initWithTable:self ndx:ndx];
}

-(RLMRow *)firstRow
{
    if (self.rowCount == 0) {
        return nil;
    }
    return [[RLMRow alloc] initWithTable:self ndx:0];
}

-(RLMRow *)lastRow
{
    if (self.rowCount == 0) {
        return nil;
    }
    return [[RLMRow alloc] initWithTable:self ndx:self.rowCount-1];
}

-(RLMRow *)insertRowAtIndex:(NSUInteger)ndx
{
    [self insertEmptyRowAtIndex:ndx];
    return [[RLMRow alloc] initWithTable:self ndx:ndx];
}

-(void)addRow:(NSObject*)data
{
    if(m_read_only) {
        @throw [NSException exceptionWithName:@"tightdb:table_is_read_only"
                                       reason:@"You tried to modify a table in read only mode"
                                     userInfo:[NSMutableDictionary dictionary]];
    }
    
    if (!data) {
        [self TDB_addEmptyRow];
        return;
    }
    tightdb::Table& table = *m_table;
    [self insertRow:data atIndex:table.size()];
}

/* Moved to private header */
-(RLMRow *)addEmptyRow
{
    return [[RLMRow alloc] initWithTable:self ndx:[self TDB_addEmptyRow]];
}


-(void)insertRow:(NSObject *)anObject atIndex:(NSUInteger)rowIndex
{
    if (!anObject) {
        [self TDBInsertRow:rowIndex];
        return;
    }
    
    tightdb::Table& table = *m_table;
    tightdb::ConstDescriptorRef desc = table.get_descriptor();
    
    if ([anObject isKindOfClass:[NSArray class]]) {
        verify_row(*desc, (NSArray *)anObject);
        insert_row(size_t(rowIndex), table, (NSArray *)anObject);
        return;
    }
    
    if ([anObject isKindOfClass:[NSDictionary class]]) {
        verify_row_with_labels(*desc, (NSDictionary *)anObject);
        insert_row_with_labels(size_t(rowIndex), table, (NSDictionary *)anObject);
        return;
    }
    
    if ([anObject isKindOfClass:[NSObject class]]) {
        verify_row_from_object(*desc, (NSObject *)anObject);
        insert_row_from_object(size_t(rowIndex), table, (NSObject *)anObject);
        return;
    }

    @throw [NSException exceptionWithName:@"tightdb:column_not_implemented"
                                   reason:@"You should either use nil, NSObject, NSDictionary, or NSArray"
                                 userInfo:nil];
}


-(void)removeAllRows
{
    if (m_read_only) {
        @throw [NSException exceptionWithName:@"tightdb:table_is_read_only"
                                       reason:@"You tried to modify an immutable table."
                                     userInfo:nil];
    }
    
    m_table->clear();
}

-(void)removeRowAtIndex:(NSUInteger)ndx
{
    if (m_read_only) {
        @throw [NSException exceptionWithName:@"tightdb:table_is_read_only"
                                       reason:@"You tried to modify an immutable table."
                                     userInfo:nil];
    }
    m_table->remove(ndx);
}

-(void)removeLastRow
{
    if (m_read_only) {
        @throw [NSException exceptionWithName:@"tightdb:table_is_read_only"
                                       reason:@"You tried to modify an immutable table."
                                     userInfo:nil];
    }
    m_table->remove_last();
}


-(BOOL)TDB_boolInColumnWithIndex:(NSUInteger)colIndex atRowIndex:(NSUInteger)rowIndex
{
    return m_table->get_bool(colIndex, rowIndex);
}

-(int64_t)TDB_intInColumnWithIndex:(NSUInteger)colIndex atRowIndex:(NSUInteger)rowIndex
{
    return m_table->get_int(colIndex, rowIndex);
}

-(float)TDB_floatInColumnWithIndex:(NSUInteger)colIndex atRowIndex:(NSUInteger)rowIndex
{
    return m_table->get_float(colIndex, rowIndex);
}

-(double)TDB_doubleInColumnWithIndex:(NSUInteger)colIndex atRowIndex:(NSUInteger)rowIndex
{
    return m_table->get_double(colIndex, rowIndex);
}

-(NSString*)TDB_stringInColumnWithIndex:(NSUInteger)colIndex atRowIndex:(NSUInteger)rowIndex
{
    return to_objc_string(m_table->get_string(colIndex, rowIndex));
}

-(NSData*)TDB_binaryInColumnWithIndex:(NSUInteger)colIndex atRowIndex:(NSUInteger)rowIndex
{
    tightdb::BinaryData bd = m_table->get_binary(colIndex, rowIndex);
    return [[NSData alloc] initWithBytes:static_cast<const void *>(bd.data()) length:bd.size()];
}

-(NSDate *)TDB_dateInColumnWithIndex:(NSUInteger)colIndex atRowIndex:(NSUInteger)rowIndex
{
    return [NSDate dateWithTimeIntervalSince1970: m_table->get_datetime(colIndex, rowIndex).get_datetime()];
}

-(RLMTable *)TDB_tableInColumnWithIndex:(NSUInteger)colIndex atRowIndex:(NSUInteger)rowIndex
{
    tightdb::DataType type = m_table->get_column_type(colIndex);
    if (type != tightdb::type_Table)
        return nil;
    tightdb::TableRef table = m_table->get_subtable(colIndex, rowIndex);
    if (!table)
        return nil;
    RLMTable * table_2 = [[RLMTable alloc] _initRaw];
    if (TIGHTDB_UNLIKELY(!table_2))
        return nil;
    [table_2 setNativeTable:table.get()];
    [table_2 setParent:self];
    [table_2 setReadOnly:m_read_only];
    return table_2;
}

// FIXME: Check that the specified class derives from RLMTable.
-(id)TDB_tableInColumnWithIndex:(NSUInteger)colIndex atRowIndex:(NSUInteger)rowIndex asTableClass:(__unsafe_unretained Class)tableClass
{
    tightdb::DataType type = m_table->get_column_type(colIndex);
    if (type != tightdb::type_Table)
        return nil;
    tightdb::TableRef table = m_table->get_subtable(colIndex, rowIndex);
    TIGHTDB_ASSERT(table);
    RLMTable * table_2 = [[tableClass alloc] _initRaw];
    if (TIGHTDB_UNLIKELY(!table))
        return nil;
    [table_2 setNativeTable:table.get()];
    [table_2 setParent:self];
    [table_2 setReadOnly:m_read_only];
    if (![table_2 _checkType])
        return nil;
    return table_2;
}

-(id)TDB_mixedInColumnWithIndex:(NSUInteger)colNdx atRowIndex:(NSUInteger)rowIndex
{
    tightdb::Mixed mixed = m_table->get_mixed(colNdx, rowIndex);
    if (mixed.get_type() != tightdb::type_Table)
        return to_objc_object(mixed);

    tightdb::TableRef table = m_table->get_subtable(colNdx, rowIndex);
    TIGHTDB_ASSERT(table);
    RLMTable * table_2 = [[RLMTable alloc] _initRaw];
    if (TIGHTDB_UNLIKELY(!table_2))
        return nil;
    [table_2 setNativeTable:table.get()];
    [table_2 setParent:self];
    [table_2 setReadOnly:m_read_only];
    if (![table_2 _checkType])
        return nil;

    return table_2;
}


-(void)TDB_setBool:(BOOL)value inColumnWithIndex:(NSUInteger)col_ndx atRowIndex:(NSUInteger)row_ndx
{
    TIGHTDB_EXCEPTION_HANDLER_SETTERS(
        m_table->set_bool(col_ndx, row_ndx, value);,
    RLMTypeBool);
}

-(void)TDB_setInt:(int64_t)value inColumnWithIndex:(NSUInteger)col_ndx atRowIndex:(NSUInteger)row_ndx
{
    TIGHTDB_EXCEPTION_HANDLER_SETTERS(
        m_table->set_int(col_ndx, row_ndx, value);,
        RLMTypeInt);
}

-(void)TDB_setFloat:(float)value inColumnWithIndex:(NSUInteger)col_ndx atRowIndex:(NSUInteger)row_ndx
{
    TIGHTDB_EXCEPTION_HANDLER_SETTERS(
        m_table->set_float(col_ndx, row_ndx, value);,
        RLMTypeFloat);
}

-(void)TDB_setDouble:(double)value inColumnWithIndex:(NSUInteger)col_ndx atRowIndex:(NSUInteger)row_ndx
{
    TIGHTDB_EXCEPTION_HANDLER_SETTERS(
        m_table->set_double(col_ndx, row_ndx, value);,
        RLMTypeDouble);
}

-(void)TDB_setString:(NSString*)value inColumnWithIndex:(NSUInteger)col_ndx atRowIndex:(NSUInteger)row_ndx
{
    TIGHTDB_EXCEPTION_HANDLER_SETTERS(
        m_table->set_string(col_ndx, row_ndx, ObjcStringAccessor(value));,
        RLMTypeString);
}

-(void)TDB_setBinary:(NSData*)value inColumnWithIndex:(NSUInteger)col_ndx atRowIndex:(NSUInteger)row_ndx
{
    TIGHTDB_EXCEPTION_HANDLER_SETTERS(
        m_table->set_binary(col_ndx, row_ndx, ((NSData *)value).rlmBinaryData);,
        RLMTypeBinary);
}

-(void)TDB_setDate:(NSDate *)value inColumnWithIndex:(NSUInteger)col_ndx atRowIndex:(NSUInteger)row_ndx
{
    TIGHTDB_EXCEPTION_HANDLER_SETTERS(
       m_table->set_datetime(col_ndx, row_ndx, tightdb::DateTime((time_t)[value timeIntervalSince1970]));,
       RLMTypeDate);
}

-(void)TDB_setTable:(RLMTable *)value inColumnWithIndex:(NSUInteger)col_ndx atRowIndex:(NSUInteger)row_ndx
{
    // TODO: Use core method for checking the equality of two table specs. Even in the typed interface
    // the user might add columns (_checkType for typed and spec against spec for dynamic).

    TIGHTDB_EXCEPTION_HANDLER_SETTERS(
        m_table->set_subtable(col_ndx, row_ndx, &[value getNativeTable]);,
        RLMTypeTable);
}

-(void)TDB_setMixed:(id)value inColumnWithIndex:(NSUInteger)col_ndx atRowIndex:(NSUInteger)row_ndx
{
    tightdb::Mixed mixed;
    to_mixed(value, mixed);
    RLMTable * subtable = mixed.get_type() == tightdb::type_Table ? (RLMTable *)value : nil;
    TIGHTDB_EXCEPTION_HANDLER_SETTERS(
        if (subtable) {
            tightdb::LangBindHelper::set_mixed_subtable(*m_table, col_ndx, row_ndx,
                                                        [subtable getNativeTable]);
        }
        else {
            m_table->set_mixed(col_ndx, row_ndx, mixed);
        },
        RLMTypeMixed);
}


-(BOOL)TDB_insertBool:(NSUInteger)col_ndx ndx:(NSUInteger)ndx value:(BOOL)value
{
    return [self TDB_insertBool:col_ndx ndx:ndx value:value error:nil];
}

-(BOOL)TDB_insertBool:(NSUInteger)col_ndx ndx:(NSUInteger)ndx value:(BOOL)value error:(NSError* __autoreleasing*)error
{
    // FIXME: Read-only errors should probably be handled by throwing
    // an exception. That is what is done in other places in this
    // binding, and it also seems like the right thing to do. This
    // method should also not take an error argument.
    if (m_read_only) {
        if (error)
            *error = make_tightdb_error(tdb_err_FailRdOnly, [NSString stringWithFormat:@"Tried to insert while read only ColumnId: %llu", (unsigned long long)col_ndx]);
        return NO;
    }
    TIGHTDB_EXCEPTION_ERRHANDLER(m_table->insert_bool(col_ndx, ndx, value);, NO);
    return YES;
}

-(BOOL)TDB_insertInt:(NSUInteger)col_ndx ndx:(NSUInteger)ndx value:(int64_t)value
{
    return [self TDB_insertInt:col_ndx ndx:ndx value:value error:nil];
}


-(BOOL)TDB_insertInt:(NSUInteger)col_ndx ndx:(NSUInteger)ndx value:(int64_t)value error:(NSError* __autoreleasing*)error
{
    // FIXME: Read-only errors should probably be handled by throwing
    // an exception. That is what is done in other places in this
    // binding, and it also seems like the right thing to do. This
    // method should also not take an error argument.
    if (m_read_only) {
        if (error)
            *error = make_tightdb_error(tdb_err_FailRdOnly, [NSString stringWithFormat:@"Tried to insert while read only ColumnId: %llu", (unsigned long long)col_ndx]);
        return NO;
    }
    TIGHTDB_EXCEPTION_ERRHANDLER(m_table->insert_int(col_ndx, ndx, value);, NO);
    return YES;
}

-(BOOL)TDB_insertFloat:(NSUInteger)col_ndx ndx:(NSUInteger)ndx value:(float)value
{
    return [self TDB_insertFloat:col_ndx ndx:ndx value:value error:nil];
}

-(BOOL)TDB_insertFloat:(NSUInteger)col_ndx ndx:(NSUInteger)ndx value:(float)value error:(NSError* __autoreleasing*)error
{
    // FIXME: Read-only errors should probably be handled by throwing
    // an exception. That is what is done in other places in this
    // binding, and it also seems like the right thing to do. This
    // method should also not take an error argument.
    if (m_read_only) {
        if (error)
            *error = make_tightdb_error(tdb_err_FailRdOnly, [NSString stringWithFormat:@"Tried to insert while read only ColumnId: %llu", (unsigned long long)col_ndx]);
        return NO;
    }
    TIGHTDB_EXCEPTION_ERRHANDLER(m_table->insert_float(col_ndx, ndx, value);, NO);
    return YES;
}

-(BOOL)TDB_insertDouble:(NSUInteger)col_ndx ndx:(NSUInteger)ndx value:(double)value
{
    return [self TDB_insertDouble:col_ndx ndx:ndx value:value error:nil];
}

-(BOOL)TDB_insertDouble:(NSUInteger)col_ndx ndx:(NSUInteger)ndx value:(double)value error:(NSError* __autoreleasing*)error
{
    // FIXME: Read-only errors should probably be handled by throwing
    // an exception. That is what is done in other places in this
    // binding, and it also seems like the right thing to do. This
    // method should also not take an error argument.
    if (m_read_only) {
        if (error)
            *error = make_tightdb_error(tdb_err_FailRdOnly, [NSString stringWithFormat:@"Tried to insert while read only ColumnId: %llu", (unsigned long long)col_ndx]);
        return NO;
    }
    TIGHTDB_EXCEPTION_ERRHANDLER(m_table->insert_double(col_ndx, ndx, value);, NO);
    return YES;
}

-(BOOL)TDB_insertString:(NSUInteger)col_ndx ndx:(NSUInteger)ndx value:(NSString*)value
{
    return [self TDB_insertString:col_ndx ndx:ndx value:value error:nil];
}

-(BOOL)TDB_insertString:(NSUInteger)col_ndx ndx:(NSUInteger)ndx value:(NSString*)value error:(NSError* __autoreleasing*)error
{
    // FIXME: Read-only errors should probably be handled by throwing
    // an exception. That is what is done in other places in this
    // binding, and it also seems like the right thing to do. This
    // method should also not take an error argument.
    if (m_read_only) {
        if (error)
            *error = make_tightdb_error(tdb_err_FailRdOnly, [NSString stringWithFormat:@"Tried to insert while read only ColumnId: %llu", (unsigned long long)col_ndx]);
        return NO;
    }
    TIGHTDB_EXCEPTION_ERRHANDLER(
        m_table->insert_string(col_ndx, ndx, ObjcStringAccessor(value));,
        NO);
    return YES;
}

-(BOOL)TDB_insertBinary:(NSUInteger)col_ndx ndx:(NSUInteger)ndx value:(NSData*)value
{
    return [self TDB_insertBinary:col_ndx ndx:ndx value:value error:nil];
}

-(BOOL)TDB_insertBinary:(NSUInteger)col_ndx ndx:(NSUInteger)ndx value:(NSData*)value error:(NSError* __autoreleasing*)error
{
    // FIXME: Read-only errors should probably be handled by throwing
    // an exception. That is what is done in other places in this
    // binding, and it also seems like the right thing to do. This
    // method should also not take an error argument.
    if (m_read_only) {
        if (error)
            *error = make_tightdb_error(tdb_err_FailRdOnly, [NSString stringWithFormat:@"Tried to insert while read only ColumnId: %llu", (unsigned long long)col_ndx]);
        return NO;
    }
    const void *data = [(NSData *)value bytes];
    tightdb::BinaryData bd(static_cast<const char *>(data), [(NSData *)value length]);
    TIGHTDB_EXCEPTION_ERRHANDLER(
        m_table->insert_binary(col_ndx, ndx, bd);,
        NO);
    return YES;
}

-(BOOL)TDB_insertBinary:(NSUInteger)col_ndx ndx:(NSUInteger)ndx data:(const char*)data size:(size_t)size
{
    return [self TDB_insertBinary:col_ndx ndx:ndx data:data size:size error:nil];
}

-(BOOL)TDB_insertBinary:(NSUInteger)col_ndx ndx:(NSUInteger)ndx data:(const char*)data size:(size_t)size error:(NSError* __autoreleasing*)error
{
    // FIXME: Read-only errors should probably be handled by throwing
    // an exception. That is what is done in other places in this
    // binding, and it also seems like the right thing to do. This
    // method should also not take an error argument.
    if (m_read_only) {
        if (error)
            *error = make_tightdb_error(tdb_err_FailRdOnly, [NSString stringWithFormat:@"Tried to insert while read only ColumnId: %llu", (unsigned long long)col_ndx]);
        return NO;
    }
    TIGHTDB_EXCEPTION_ERRHANDLER(
        m_table->insert_binary(col_ndx, ndx, tightdb::BinaryData(data, size));,
        NO);
    return YES;
}

-(BOOL)TDB_insertDate:(NSUInteger)col_ndx ndx:(NSUInteger)ndx value:(NSDate *)value
{
    return [self TDB_insertDate:col_ndx ndx:ndx value:value error:nil];
}

-(BOOL)TDB_insertDate:(NSUInteger)col_ndx ndx:(NSUInteger)ndx value:(NSDate *)value error:(NSError* __autoreleasing*)error
{
    // FIXME: Read-only errors should probably be handled by throwing
    // an exception. That is what is done in other places in this
    // binding, and it also seems like the right thing to do. This
    // method should also not take an error argument.
    if (m_read_only) {
        if (error)
            *error = make_tightdb_error(tdb_err_FailRdOnly, [NSString stringWithFormat:@"Tried to insert while read only ColumnId: %llu", (unsigned long long)col_ndx]);
        return NO;
    }
    TIGHTDB_EXCEPTION_ERRHANDLER(m_table->insert_datetime(col_ndx, ndx, [value timeIntervalSince1970]);, NO);
    return YES;
}

-(BOOL)TDB_insertDone
{
    return [self TDB_insertDoneWithError:nil];
}

-(BOOL)TDB_insertDoneWithError:(NSError* __autoreleasing*)error
{
    // FIXME: This method should probably not take an error argument.
    TIGHTDB_EXCEPTION_ERRHANDLER(m_table->insert_done();, NO);
    return YES;
}




-(BOOL)TDB_insertSubtable:(NSUInteger)col_ndx ndx:(NSUInteger)row_ndx
{
    return [self TDB_insertSubtable:col_ndx ndx:row_ndx error:nil];
}

-(BOOL)TDB_insertSubtable:(NSUInteger)col_ndx ndx:(NSUInteger)row_ndx error:(NSError* __autoreleasing*)error
{
    // FIXME: Read-only errors should probably be handled by throwing
    // an exception. That is what is done in other places in this
    // binding, and it also seems like the right thing to do. This
    // method should also not take an error argument.
    if (m_read_only) {
        if (error)
            *error = make_tightdb_error(tdb_err_FailRdOnly, [NSString stringWithFormat:@"Tried to insert while read only ColumnId: %llu", (unsigned long long)col_ndx]);
        return NO;
    }
    TIGHTDB_EXCEPTION_ERRHANDLER(m_table->insert_subtable(col_ndx, row_ndx);, NO);
    return YES;
}

-(BOOL)TDB_insertSubtableCopy:(NSUInteger)col_ndx row:(NSUInteger)row_ndx subtable:(RLMTable *)subtable
{
    return [self TDB_insertSubtableCopy:col_ndx row:row_ndx subtable:subtable error:nil];
}


-(BOOL)TDB_insertSubtableCopy:(NSUInteger)col_ndx row:(NSUInteger)row_ndx subtable:(RLMTable *)subtable error:(NSError* __autoreleasing*)error
{
    // FIXME: Read-only errors should probably be handled by throwing
    // an exception. That is what is done in other places in this
    // binding, and it also seems like the right thing to do. This
    // method should also not take an error argument.
    if (m_read_only) {
        if (error)
            *error = make_tightdb_error(tdb_err_FailRdOnly, [NSString stringWithFormat:@"Tried to insert while read only ColumnId: %llu", (unsigned long long)col_ndx]);
        return NO;
    }
    TIGHTDB_EXCEPTION_ERRHANDLER(
        tightdb::LangBindHelper::insert_subtable(*m_table, col_ndx, row_ndx, [subtable getNativeTable]);,
        NO);
    return YES;
}




-(RLMType)mixedTypeForColumnWithIndex:(NSUInteger)colIndex atRowIndex:(NSUInteger)rowIndex
{
    return RLMType(m_table->get_mixed_type(colIndex, rowIndex));
}

-(BOOL)TDB_insertMixed:(NSUInteger)col_ndx ndx:(NSUInteger)row_ndx value:(id)value
{
    return [self TDB_insertMixed:col_ndx ndx:row_ndx value:value error:nil];
}

-(BOOL)TDB_insertMixed:(NSUInteger)col_ndx ndx:(NSUInteger)row_ndx value:(id)value error:(NSError* __autoreleasing*)error
{
    if (m_read_only) {
        if (error)
            *error = make_tightdb_error(tdb_err_FailRdOnly, [NSString stringWithFormat:@"Tried to insert while read only ColumnId: %llu", (unsigned long long)col_ndx]);
        return NO;
    }
    tightdb::Mixed mixed;
    RLMTable * subtable;
    if ([value isKindOfClass:[RLMTable class]]) {
        subtable = (RLMTable *)value;
    }
    else {
        to_mixed(value, mixed);
    }
    TIGHTDB_EXCEPTION_ERRHANDLER(
        if (subtable) {
            tightdb::LangBindHelper::insert_mixed_subtable(*m_table, col_ndx, row_ndx,
                                                           [subtable getNativeTable]);
        }
        else {
            m_table->insert_mixed(col_ndx, row_ndx, mixed);
        },
        NO);
    return YES;
}


-(NSUInteger)addColumnWithName:(NSString*)name type:(RLMType)type
{
    return [self addColumnWithType:type andName:name error:nil];
}

-(NSUInteger)addColumnWithType:(RLMType)type andName:(NSString*)name error:(NSError* __autoreleasing*)error
{
    TIGHTDB_EXCEPTION_ERRHANDLER(
        return m_table->add_column(tightdb::DataType(type), ObjcStringAccessor(name));,
        0);
}

-(void)renameColumnWithIndex:(NSUInteger)colIndex to:(NSString *)newName
{
    TIGHTDB_EXCEPTION_HANDLER_COLUMN_INDEX_VALID(colIndex);
    m_table->rename_column(colIndex, ObjcStringAccessor(newName));
}


-(void)removeColumnWithIndex:(NSUInteger)columnIndex
{
    TIGHTDB_EXCEPTION_HANDLER_COLUMN_INDEX_VALID(columnIndex);
    
    try {
        m_table->remove_column(columnIndex);
    }
    catch(std::exception& ex) {
        @throw[NSException exceptionWithName:@"tightdb:core_exception"
                                      reason:[NSString stringWithUTF8String:ex.what()]
                                    userInfo:nil];
    }
}

-(NSUInteger)findRowIndexWithBool:(BOOL)aBool inColumnWithIndex:(NSUInteger)colIndex
{
    return was_not_found(m_table->find_first_bool(colIndex, aBool));
}
-(NSUInteger)findRowIndexWithInt:(int64_t)anInt inColumnWithIndex:(NSUInteger)colIndex
{
    return was_not_found(m_table->find_first_int(colIndex, anInt));
}
-(NSUInteger)findRowIndexWithFloat:(float)aFloat inColumnWithIndex:(NSUInteger)colIndex
{
    return was_not_found(m_table->find_first_float(colIndex, aFloat));
}
-(NSUInteger)findRowIndexWithDouble:(double)aDouble inColumnWithIndex:(NSUInteger)colIndex
{
    return was_not_found(m_table->find_first_double(colIndex, aDouble));
}
-(NSUInteger)findRowIndexWithString:(NSString *)aString inColumnWithIndex:(NSUInteger)colIndex
{
    return was_not_found(m_table->find_first_string(colIndex, ObjcStringAccessor(aString)));
}
-(NSUInteger)findRowIndexWithBinary:(NSData *)aBinary inColumnWithIndex:(NSUInteger)colIndex
{
    const void *data = [(NSData *)aBinary bytes];
    tightdb::BinaryData bd(static_cast<const char *>(data), [(NSData *)aBinary length]);
    return was_not_found(m_table->find_first_binary(colIndex, bd));
}
-(NSUInteger)findRowIndexWithDate:(NSDate *)aDate inColumnWithIndex:(NSUInteger)colIndex
{
    return was_not_found(m_table->find_first_datetime(colIndex, [aDate timeIntervalSince1970]));
}
-(NSUInteger)findRowIndexWithMixed:(id)aMixed inColumnWithIndex:(NSUInteger)colIndex
{
    static_cast<void>(colIndex);
    static_cast<void>(aMixed);
    [NSException raise:@"NotImplemented" format:@"Not implemented"];
    // FIXME: Implement this!
//    return _table->find_first_mixed(col_ndx, [value getNativeMixed]);
    return 0;
}

-(RLMView*)findAllRowsWithBool:(BOOL)aBool inColumnWithIndex:(NSUInteger)colIndex
{
    tightdb::TableView view = m_table->find_all_bool(colIndex, aBool);
    return [RLMView viewWithTable:self andNativeView:view];
}
-(RLMView*)findAllRowsWithInt:(int64_t)anInt inColumnWithIndex:(NSUInteger)colIndex
{
    tightdb::TableView view = m_table->find_all_int(colIndex, anInt);
    return [RLMView viewWithTable:self andNativeView:view];
}
-(RLMView*)findAllRowsWithFloat:(float)aFloat inColumnWithIndex:(NSUInteger)colIndex
{
    tightdb::TableView view = m_table->find_all_float(colIndex, aFloat);
    return [RLMView viewWithTable:self andNativeView:view];
}
-(RLMView*)findAllRowsWithDouble:(double)aDouble inColumnWithIndex:(NSUInteger)colIndex
{
    tightdb::TableView view = m_table->find_all_double(colIndex, aDouble);
    return [RLMView viewWithTable:self andNativeView:view];
}
-(RLMView*)findAllRowsWithString:(NSString *)aString inColumnWithIndex:(NSUInteger)colIndex
{
    tightdb::TableView view = m_table->find_all_string(colIndex, ObjcStringAccessor(aString));
    return [RLMView viewWithTable:self andNativeView:view];
}
-(RLMView*)findAllRowsWithBinary:(NSData *)aBinary inColumnWithIndex:(NSUInteger)colIndex
{
    tightdb::TableView view = m_table->find_all_binary(colIndex, aBinary.rlmBinaryData);
    return [RLMView viewWithTable:self andNativeView:view];
}
-(RLMView*)findAllRowsWithDate:(NSDate *)aDate inColumnWithIndex:(NSUInteger)colIndex
{
    tightdb::TableView view = m_table->find_all_datetime(colIndex, [aDate timeIntervalSince1970]);
    return [RLMView viewWithTable:self andNativeView:view];
}
-(RLMView*)findAllRowsWithMixed:(id)aMixed inColumnWithIndex:(NSUInteger)colIndex
{
    static_cast<void>(colIndex);
    static_cast<void>(aMixed);
    [NSException raise:@"NotImplemented" format:@"Not implemented"];
    // FIXME: Implement this!
//    tightdb::TableView view = m_table->find_all_mixed(col_ndx, [value getNativeMixed]);
//    return [RLMView viewWithTable:self andNativeView:view];
    return 0;
}

-(RLMQuery*)where
{
    return [self whereWithError:nil];
}

-(RLMQuery*)whereWithError:(NSError* __autoreleasing*)error
{
    return [[RLMQuery alloc] initWithTable:self error:error];
}

-(RLMView *)distinctValuesInColumnWithIndex:(NSUInteger)colIndex
{
    if (!([self columnTypeOfColumnWithIndex:colIndex] == RLMTypeString)) {
        @throw [NSException exceptionWithName:@"tightdb:column_type_not_supported"
                                       reason:@"Distinct currently only supported on columns of type RLMTypeString"
                                     userInfo:nil];
    }
    if (![self isIndexCreatedInColumnWithIndex:colIndex]) {
        @throw [NSException exceptionWithName:@"tightdb:column_not_indexed"
                                       reason:@"An index must be created on the column to get distinct values"
                                     userInfo:nil];
    }
    
    tightdb::TableView distinctView = m_table->get_distinct_view(colIndex);
    return [RLMView viewWithTable:self andNativeView:distinctView];
}

namespace {

// small helper to create the many exceptions thrown when parsing predicates
inline NSException * predicate_exception(NSString * name, NSString * reason) {
    return [NSException exceptionWithName:[NSString stringWithFormat:@"filterWithPredicate:orderedBy: - %@", name] reason:reason userInfo:nil];
}

// validate that we support the passed in expression type
inline NSExpressionType validated_expression_type(NSExpression * expression) {
    if (expression.expressionType != NSConstantValueExpressionType &&
        expression.expressionType != NSKeyPathExpressionType) {
        @throw predicate_exception(@"Invalid expression type", @"Only support NSConstantValueExpressionType and NSKeyPathExpressionType");
    }
    return expression.expressionType;
}

// return the column index for a validated column name
inline NSUInteger validated_column_index(RLMTable * table, NSString * columnName) {
    NSUInteger index = [table indexOfColumnWithName:columnName];
    if (index == NSNotFound) {
        @throw predicate_exception(@"Invalid column name",
            [NSString stringWithFormat:@"Column name %@ not found in table", columnName]);
    }
    return index;
}


// apply an expression between two columns to a query
/*
void update_query_with_column_expression(RLMTable * table, tightdb::Query & query,
    NSString * col1, NSString * col2, NSPredicateOperatorType operatorType) {
    
    // only support equality for now
    if (operatorType != NSEqualToPredicateOperatorType) {
        @throw predicate_exception(@"Invalid predicate comparison type", @"only support equality comparison type");
    }
    
    // validate column names
    NSUInteger index1 = validated_column_index(table, col1);
    NSUInteger index2 = validated_column_index(table, col2);
    
    // make sure they are the same type
    tightdb::DataType type1 = table->m_table->get_column_type(index1);
    tightdb::DataType type2 = table->m_table->get_column_type(index2);

    if (type1 == type2) {
        @throw predicate_exception(@"Invalid predicate expression", @"Columns must be the same type");
    }

    // not suppoting for now - if we changed names for column comparisons so that we could
    // use templated function for all numeric types this would be much easier
    @throw predicate_exception(@"Unsupported predicate", @"Not suppoting column comparison for now");
}
 */

// add a clause for numeric constraints based on operator type
template <typename T>
void add_numeric_constraint_to_query(tightdb::Query & query,
                                     tightdb::DataType datatype,
                                     NSPredicateOperatorType operatorType,
                                     NSUInteger index,
                                     T value) {
    switch (operatorType) {
        case NSLessThanPredicateOperatorType:
            query.less(index, value);
            break;
        case NSLessThanOrEqualToPredicateOperatorType:
            query.less_equal(index, value);
            break;
        case NSGreaterThanPredicateOperatorType:
            query.greater(index, value);
            break;
        case NSGreaterThanOrEqualToPredicateOperatorType:
            query.greater_equal(index, value);
            break;
        case NSEqualToPredicateOperatorType:
            query.equal(index, value);
            break;
        case NSNotEqualToPredicateOperatorType:
            query.not_equal(index, value);
            break;
        default:
            @throw predicate_exception(@"Invalid operator type", [NSString stringWithFormat:@"Operator type %lu not supported for type %u", (unsigned long)operatorType, datatype]);
            break;
    }
}

void add_bool_constraint_to_query(tightdb::Query & query,
                                    NSPredicateOperatorType operatorType,
                                    NSUInteger index,
                                    bool value) {
    switch (operatorType) {
        case NSEqualToPredicateOperatorType:
            query.equal(index, value);
            break;
        case NSNotEqualToPredicateOperatorType:
            query.not_equal(index, value);
            break;
        default:
            @throw predicate_exception(@"Invalid operator type", [NSString stringWithFormat:@"Operator type %lu not supported for bool type", (unsigned long)operatorType]);
            break;
    }
}

void add_string_constraint_to_query(tightdb::Query & query,
                                    NSPredicateOperatorType operatorType,
                                    NSUInteger index,
                                    NSString * value) {
    
    tightdb::StringData sd([(NSString *)value UTF8String]);
    query.equal(index, sd);
    switch (operatorType) {
        case NSBeginsWithPredicateOperatorType:
            query.begins_with(index, sd);
            break;
        case NSEndsWithPredicateOperatorType:
            query.ends_with(index, sd);
            break;
        case NSContainsPredicateOperatorType:
            query.contains(index, sd);
            break;
        case NSEqualToPredicateOperatorType:
            query.equal(index, sd);
            break;
        case NSNotEqualToPredicateOperatorType:
            query.not_equal(index, sd);
            break;
        default:
            @throw predicate_exception(@"Invalid operator type", [NSString stringWithFormat:@"Operator type %lu not supported for string type", (unsigned long)operatorType]);
            break;
    }
}

void update_query_with_value_expression(RLMTable * table, tightdb::Query & query,
    NSString * columnName, id value, NSPredicateOperatorType operatorType) {

    // validate object type
    NSUInteger index = validated_column_index(table, columnName);
    tightdb::DataType type = table->m_table->get_column_type(index);
    if (!verify_object_is_type(value, type)) {
        @throw predicate_exception(@"Invalid value",
                                   [NSString stringWithFormat:@"object must be of type %i", type]);
    }
    
    // finally cast to native types and add query clause
    switch (type) {
        case tightdb::type_Bool:
            add_bool_constraint_to_query(query, operatorType, index,
                                         bool([(NSNumber *)value boolValue]));
            break;
        case tightdb::type_DateTime:
            // TODO: change datetime so method signaturs match other numeric types
            @throw predicate_exception(@"Unsupported predicate value type",
                                       @"Not supporting dates temporarily");
            break;
        case tightdb::type_Double:
            add_numeric_constraint_to_query(query, type, operatorType,
                                            index, double([(NSNumber *)value doubleValue]));
            break;
        case tightdb::type_Float:
            add_numeric_constraint_to_query(query, type, operatorType,
                                            index, float([(NSNumber *)value floatValue]));
            break;
        case tightdb::type_Int:
            add_numeric_constraint_to_query(query, type, operatorType,
                                            index, int([(NSNumber *)value intValue]));
            break;
        case tightdb::type_String:
            add_string_constraint_to_query(query, operatorType, index, (NSString *)value);
            break;
        default:
            @throw predicate_exception(@"Unsupported predicate value type",
                [NSString stringWithFormat:@"Object type %i not supported", type]);
    }
}

void update_query_with_predicate(NSPredicate * predicate,
    RLMTable * table, tightdb::Query & query) {
    
    // compound predicates
    if ([predicate isMemberOfClass:[NSCompoundPredicate class]]) {
        NSCompoundPredicate * comp = (NSCompoundPredicate *)predicate;
        if ([comp compoundPredicateType] == NSAndPredicateType) {
            // add all of the subprediates
            query.group();
            for (NSPredicate * subp in comp.subpredicates) {
                update_query_with_predicate(subp, table, query);
            }
            query.end_group();
        }
        else if ([comp compoundPredicateType] == NSOrPredicateType) {
            // add all of the subprediates with ors inbetween
            query.group();
            for (NSUInteger i = 0; i < comp.subpredicates.count; i++) {
                NSPredicate * subp = comp.subpredicates[i];
                if (i > 0) {
                    query.Or();
                }
                update_query_with_predicate(subp, table, query);
            }
            query.end_group();
        }
        else {
            @throw predicate_exception(@"Invalid compound predicate type",
                                       @"Only support AND and OR predicate types");
        }
    }
    else if ([predicate isMemberOfClass:[NSComparisonPredicate class]]) {
        NSComparisonPredicate * compp = (NSComparisonPredicate *)predicate;
 
        // validate expressions
        NSExpressionType exp1Type = validated_expression_type(compp.leftExpression);
        NSExpressionType exp2Type = validated_expression_type(compp.rightExpression);

        // figure out if we have column expression or value expression and update query accordingly
        // we are limited here to KeyPath expressions and constantValue expressions from validation
        if (exp1Type == NSKeyPathExpressionType) {
            if (exp2Type == NSKeyPathExpressionType) {
                @throw predicate_exception(@"Unsupported predicate", @"Not suppoting column comparison for now");
//                update_query_with_column_expression(table, query, compp.leftExpression.keyPath,
//                    compp.rightExpression.keyPath, compp.predicateOperatorType);
            }
            else {
                update_query_with_value_expression(table, query, compp.leftExpression.keyPath, compp.rightExpression.constantValue, compp.predicateOperatorType);
            }
        }
        else {
            if (exp2Type == NSKeyPathExpressionType) {
                update_query_with_value_expression(table, query, compp.rightExpression.keyPath, compp.leftExpression.constantValue, compp.predicateOperatorType);
            }
            else {
                @throw predicate_exception(@"Invalid predicate expressions",
                                           @"Tring to compare two constant values");
            }
        }
    }
    else {
        // invalid predicate type
        @throw predicate_exception(@"Invalid predicate",
                                   @"Only support compound and comparison predicates");
    }
}

tightdb::Query queryFromPredicate(RLMTable *table, id condition)
{
    tightdb::Query query = table->m_table->where();

    // parse and apply predicate tree
    if (condition) {
        if ([condition isKindOfClass:[NSString class]]) {
            NSPredicate *predicate = [NSPredicate predicateWithFormat:condition];
            update_query_with_predicate(predicate, table, query);
        }
        else if ([condition isKindOfClass:[NSPredicate class]]) {
            update_query_with_predicate(condition, table, query);
        }
        else {
            @throw predicate_exception(@"Invalid argument", @"Condition should be predicate as string or NSPredicate object");
        }
    }

    return query;
}

} //namespace

-(RLMRow *)find:(id)condition
{
    tightdb::Query query = queryFromPredicate(self, condition);

    size_t row_ndx = query.find();

    if (row_ndx == tightdb::not_found)
        return nil;

    return [[RLMRow alloc] initWithTable:self ndx:row_ndx];
}

-(RLMView *)where:(id)condition
{
    tightdb::Query query = queryFromPredicate(self, condition);

    // create view
    tightdb::TableView view = query.find_all();

    // create objc view and return
    return [RLMView viewWithTable:self andNativeView:view];
}

-(RLMView *)where:(id)condition orderBy:(id)order
{
    tightdb::Query query = queryFromPredicate(self, condition);

    // create view
    tightdb::TableView view = query.find_all();

    // apply order
    if (order) {
        NSString *columnName;
        BOOL ascending = YES;

        if ([order isKindOfClass:[NSString class]]) {
            columnName = order;
        }
        else if ([order isKindOfClass:[NSSortDescriptor class]]) {
            columnName = ((NSSortDescriptor*)order).key;
            ascending = ((NSSortDescriptor*)order).ascending;
        }
        else {
            @throw predicate_exception(@"Invalid order type",
                                       @"Order must be column name or NSSortDescriptor");
        }

        NSUInteger index = validated_column_index(self, columnName);
        RLMType columnType = [self columnTypeOfColumnWithIndex:index];

        if (columnType != RLMTypeInt && columnType != RLMTypeBool && columnType != RLMTypeDate) {
            @throw predicate_exception(@"Invalid sort column type",
                                       @"Sort only supported on Integer, Date and Boolean columns.");
        }

        view.sort(index, ascending);
    }

    // create objc view and return
    return [RLMView viewWithTable:self andNativeView:view];
}

-(BOOL)isIndexCreatedInColumnWithIndex:(NSUInteger)colIndex
{
    return m_table->has_index(colIndex);
}

-(void)createIndexInColumnWithIndex:(NSUInteger)colIndex
{
    m_table->set_index(colIndex);
}

-(BOOL)optimize
{
    return [self optimizeWithError:nil];
}

-(BOOL)optimizeWithError:(NSError* __autoreleasing*)error
{
    TIGHTDB_EXCEPTION_ERRHANDLER(m_table->optimize();, NO);
    return YES;
}

-(NSUInteger)countRowsWithInt:(int64_t)anInt inColumnWithIndex:(NSUInteger)colIndex
{
    return m_table->count_int(colIndex, anInt);
}
-(NSUInteger)countRowsWithFloat:(float)aFloat inColumnWithIndex:(NSUInteger)colIndex
{
    return m_table->count_float(colIndex, aFloat);
}
-(NSUInteger)countRowsWithDouble:(double)aDouble inColumnWithIndex:(NSUInteger)colIndex
{
    return m_table->count_double(colIndex, aDouble);
}
-(NSUInteger)countRowsWithString:(NSString *)aString inColumnWithIndex:(NSUInteger)colIndex
{
    return m_table->count_string(colIndex, ObjcStringAccessor(aString));
}

-(int64_t)sumIntColumnWithIndex:(NSUInteger)colIndex
{
    return m_table->sum_int(colIndex);
}
-(double)sumFloatColumnWithIndex:(NSUInteger)colIndex
{
    return m_table->sum_float(colIndex);
}
-(double)sumDoubleColumnWithIndex:(NSUInteger)colIndex
{
    return m_table->sum_double(colIndex);
}

-(int64_t)maxIntInColumnWithIndex:(NSUInteger)colIndex
{
    return m_table->maximum_int(colIndex);
}
-(float)maxFloatInColumnWithIndex:(NSUInteger)colIndex
{
    return m_table->maximum_float(colIndex);
}
-(double)maxDoubleInColumnWithIndex:(NSUInteger)colIndex
{
    return m_table->maximum_double(colIndex);
}

-(int64_t)minIntInColumnWithIndex:(NSUInteger)colIndex
{
    return m_table->minimum_int(colIndex);
}
-(float)minFloatInColumnWithIndex:(NSUInteger)colIndex
{
    return m_table->minimum_float(colIndex);
}
-(double)minDoubleInColumnWithIndex:(NSUInteger)colIndex
{
    return m_table->minimum_double(colIndex);
}

-(double)avgIntColumnWithIndex:(NSUInteger)colIndex
{
    return m_table->average_int(colIndex);
}
-(double)avgFloatColumnWithIndex:(NSUInteger)colIndex
{
    return m_table->average_float(colIndex);
}
-(double)avgDoubleColumnWithIndex:(NSUInteger)colIndex
{
    return m_table->average_double(colIndex);
}

-(BOOL)_addColumns
{
    return YES; // Must be overridden in typed table classes.
}

@end

