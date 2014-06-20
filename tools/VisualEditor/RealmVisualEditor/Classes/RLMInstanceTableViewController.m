//
//  RLMInstanceTableViewController.m
//  RealmVisualEditor
//
//  Created by Jesper Zuschlag on 20/06/14.
//  Copyright (c) 2014 Realm inc. All rights reserved.
//

#import "RLMInstanceTableViewController.h"

#import "RLMRealmBrowserWindowController.h"
#import "RLMObject+ResolvedClass.h"
#import "NSTableColumn+Resize.h"

@implementation RLMInstanceTableViewController

- (void)viewDidLoad
{
    // Perform some extra inititialization on the tableview
    
    // [self.instancesTableView setDoubleAction:@selector(userDoubleClicked:)];
}

#pragma mark - NSTableViewDataSource implementation

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    if (tableView == self.instancesTableView) {
        return self.parentWindowController. modelDocument.selectedObjectNode.instanceCount;
    }
    
    return 0;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
    if (tableView == self.instancesTableView) {
        
        NSUInteger columnIndex = [self.instancesTableView.tableColumns
                                  indexOfObject:tableColumn];
        
        RLMClazzProperty *clazzProperty = self.parentWindowController.modelDocument.selectedObjectNode.propertyColumns[columnIndex];
        NSString *propertyName = clazzProperty.name;
        RLMObject *selectedInstance = [self.parentWindowController.modelDocument.selectedObjectNode instanceAtIndex:rowIndex];
        NSObject *propertyValue = selectedInstance[propertyName];
        
        switch (clazzProperty.type) {
            case RLMPropertyTypeInt:
            case RLMPropertyTypeBool:
            case RLMPropertyTypeFloat:
            case RLMPropertyTypeDouble:
                if ([propertyValue isKindOfClass:[NSNumber class]]) {
                    return propertyValue;
                }
                break;
                
                
            case RLMPropertyTypeString:
                if ([propertyValue isKindOfClass:[NSString class]]) {
                    return propertyValue;
                }
                break;
                
            case RLMPropertyTypeData:
                return @"<Data>";
                
            case RLMPropertyTypeAny:
                return @"<Any>";
                
            case RLMPropertyTypeDate:
                if ([propertyValue isKindOfClass:[NSDate class]]) {
                    return propertyValue;
                }
                break;
                
            case RLMPropertyTypeArray: {
                RLMArray *referredObject = (RLMArray *)propertyValue;
                return [NSString stringWithFormat:@"-> %@[%lu]", referredObject.objectClassName, (unsigned long)referredObject.count];
            }
                
            case RLMPropertyTypeObject: {
                RLMObject *referredObject = (RLMObject *)propertyValue;
                RLMObjectSchema *objectSchema = referredObject.schema;
                return [NSString stringWithFormat:@"-> %@", objectSchema.className];
            }
                
            default:
                break;
        }
    }
    
    return nil;
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
    if (tableView == self.instancesTableView) {
        NSUInteger columnIndex = [self.instancesTableView.tableColumns indexOfObject:tableColumn];
        RLMClazzProperty *propertyNode = self.parentWindowController.modelDocument.selectedObjectNode.propertyColumns[columnIndex];
        NSString *propertyName = propertyNode.name;
        
        RLMObject *selectedObject = [self.parentWindowController.modelDocument.selectedObjectNode instanceAtIndex:rowIndex];
        
        RLMRealm *realm = self.parentWindowController.modelDocument.presentedRealm.realm;
        
        [realm beginWriteTransaction];
        
        switch (propertyNode.type) {
            case RLMPropertyTypeBool:
                if ([object isKindOfClass:[NSNumber class]]) {
                    selectedObject[propertyName] = @(((NSNumber *)object).boolValue);
                }
                break;
                
            case RLMPropertyTypeInt:
                if ([object isKindOfClass:[NSNumber class]]) {
                    selectedObject[propertyName] = @(((NSNumber *)object).integerValue);
                }
                break;
                
            case RLMPropertyTypeFloat:
                if ([object isKindOfClass:[NSNumber class]]) {
                    selectedObject[propertyName] = @(((NSNumber *)object).floatValue);
                }
                break;
                
            case RLMPropertyTypeDouble:
                if ([object isKindOfClass:[NSNumber class]]) {
                    selectedObject[propertyName] = @(((NSNumber *)object).doubleValue);
                }
                break;
                
            case RLMPropertyTypeString:
                if ([object isKindOfClass:[NSString class]]) {
                    selectedObject[propertyName] = object;
                }
                break;
                
            case RLMPropertyTypeDate:
            case RLMPropertyTypeData:
            case RLMPropertyTypeObject:
            case RLMPropertyTypeArray:
                break;
                
            default:
                break;
        }
        
        [realm commitWriteTransaction];
    }
}

#pragma mark - NSTableViewDelegate implementation

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    
}

- (void)tableView:(NSTableView *)tableView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
    if (tableView == self.instancesTableView) {
        NSUInteger columnIndex = [self.instancesTableView.tableColumns indexOfObject:tableColumn];
        RLMClazzProperty *propertyNode = self.parentWindowController.modelDocument.selectedObjectNode.propertyColumns[columnIndex];
        
        switch (propertyNode.type) {
            case RLMPropertyTypeBool:
            case RLMPropertyTypeInt: {
                NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
                formatter.allowsFloats = NO;
                ((NSCell *)cell).formatter = formatter;
                break;
            }
                
            case RLMPropertyTypeFloat:
            case RLMPropertyTypeDouble: {
                NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
                formatter.allowsFloats = YES;
                formatter.numberStyle = NSNumberFormatterDecimalStyle;
                ((NSCell *)cell).formatter = formatter;
                break;
            }
                
            case RLMPropertyTypeDate: {
                NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
                formatter.dateStyle = NSDateFormatterMediumStyle;
                formatter.timeStyle = NSDateFormatterShortStyle;
                ((NSCell *)cell).formatter = formatter;
                break;
            }
                
            case RLMPropertyTypeData: {
                break;
            }
                
            case RLMPropertyTypeString:
            case RLMPropertyTypeObject:
            case RLMPropertyTypeArray:
                break;
                
            default:
                break;
        }
    }
}

- (NSString *)tableView:(NSTableView *)tableView toolTipForCell:(NSCell *)cell rect:(NSRectPointer)rect tableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row mouseLocation:(NSPoint)mouseLocation
{
    if (tableView == self.instancesTableView) {
        NSUInteger columnIndex = [self.instancesTableView.tableColumns indexOfObject:tableColumn];
        RLMClazzProperty *propertyNode = self.parentWindowController.modelDocument.selectedObjectNode.propertyColumns[columnIndex];
        
        RLMObject *selectedInstance = [self.parentWindowController.modelDocument.selectedObjectNode instanceAtIndex:row];
        NSObject *propertyValue = selectedInstance[propertyNode.name];
        
        switch (propertyNode.type) {
            case RLMPropertyTypeDate: {
                if ([propertyValue isKindOfClass:[NSDate class]]) {
                    NSDate *dateValue = (NSDate *)propertyValue;
                    
                    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
                    formatter.dateStyle = NSDateFormatterFullStyle;
                    formatter.timeStyle = NSDateFormatterFullStyle;
                    
                    return [formatter stringFromDate:dateValue];
                }
                break;
            }
                
            case RLMPropertyTypeObject: {
                if ([propertyValue isKindOfClass:[RLMObject class]]) {
                    RLMObject *referredObject = (RLMObject *)propertyValue;
                    RLMObjectSchema *objectSchema = referredObject.schema;
                    NSArray *properties = objectSchema.properties;
                    
                    NSString *toolTipString = @"";
                    for (RLMProperty *property in properties) {
                        toolTipString = [toolTipString stringByAppendingFormat:@" %@:%@", property.name, referredObject[property.name]];
                    }
                    
                    return toolTipString;
                }
                
                break;
            }
                
            case RLMPropertyTypeArray: {
                if ([propertyValue isKindOfClass:[RLMArray class]]) {
                    RLMArray *referredArray = (RLMArray *)propertyValue;
                    
                    // In order to avoid that we procedure very long tooltips for arrays we have
                    // an upper limit on how many entries we will display. If the total item count
                    // of the array is within the limit we simply use the default description of
                    // the array, otherwise we construct the tooltip explicitly by concatenating the
                    // descriptions of the all the first array items within the limit + an ellipis.
                    if (referredArray.count <= kMaxNumberOfArrayEntriesInToolTip) {
                        return referredArray.description;
                    }
                    else {
                        NSString *result = @"";
                        for (NSUInteger index = 0; index < kMaxNumberOfArrayEntriesInToolTip; index++) {
                            RLMObject *arrayItem = referredArray[index];
                            NSString *description = [arrayItem.description stringByReplacingOccurrencesOfString:@"\n"
                                                                                                     withString:@"\n\t"];
                            description = [NSString stringWithFormat:@"\t[%lu] %@", index, description];
                            if (index < kMaxNumberOfArrayEntriesInToolTip - 1) {
                                description = [description stringByAppendingString:@","];
                            }
                            result = [[result stringByAppendingString:description] stringByAppendingString:@"\n"];
                        }
                        result = [@"RLMArray (\n" stringByAppendingString:[result stringByAppendingString:@"\t...\n)"]];
                        return result;
                    }
                }
                break;
            }
                
            default:
                
                break;
        }
    }
    
    return nil;
}

- (BOOL)tableView:(NSTableView *)tableView shouldEditTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    if (tableView == self.instancesTableView) {
        NSUInteger columnIndex = [self.instancesTableView.tableColumns indexOfObject:tableColumn];
        RLMClazzProperty *propertyNode = self.parentWindowController.modelDocument.selectedObjectNode.propertyColumns[columnIndex];
        
        if (propertyNode.type == RLMPropertyTypeDate) {
            // Create a frame which covers the cell to be edited
            NSRect frame = [tableView frameOfCellAtColumn:[[tableView tableColumns] indexOfObject:tableColumn]
                                                      row:row];
            
            frame.origin.x -= [tableView intercellSpacing].width * 0.5;
            frame.origin.y -= [tableView intercellSpacing].height * 0.5;
            frame.size.width += [tableView intercellSpacing].width * 0.5;
            frame.size.height = 23;
            
            // Set up a date picker with no border or background
            NSDatePicker *datepicker = [[NSDatePicker alloc] initWithFrame:frame];
            datepicker.bordered = NO;
            datepicker.drawsBackground = NO;
            datepicker.datePickerStyle = NSTextFieldAndStepperDatePickerStyle;
            datepicker.datePickerElements = NSHourMinuteSecondDatePickerElementFlag | NSYearMonthDayDatePickerElementFlag | NSTimeZoneDatePickerElementFlag;
            
            RLMObject *selectedObject = [self.parentWindowController.modelDocument.selectedObjectNode instanceAtIndex:row];
            NSString *propertyName = propertyNode.name;
            
            datepicker.dateValue = selectedObject[propertyName];
            
            // Create a menu with a single menu item, and set the date picker as the menu item's view
            NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
            NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@""
                                                          action:NULL
                                                   keyEquivalent:@""];
            item.view = datepicker;
            [menu addItem:item];
            
            // Display the menu, and if the user pressed enter rather than clicking away or hitting escape then process our new timestamp
            BOOL userAcceptedEdit = [menu popUpMenuPositioningItem:nil
                                                        atLocation:frame.origin
                                                            inView:tableView];
            if (userAcceptedEdit) {
                RLMRealm *realm = self.parentWindowController.modelDocument.presentedRealm.realm;
                
                [realm beginWriteTransaction];
                selectedObject[propertyName] = datepicker.dateValue;
                [realm commitWriteTransaction];
            }
        }
        else {
            return YES;
        }
    }
    
    return NO;
}

#pragma mark - Public methods - NSTableView eventHandling

- (IBAction)userDoubleClicked:(id)sender
{
    NSInteger column = self.instancesTableView.clickedColumn;
    NSInteger row = self.instancesTableView.clickedRow;
    
    if (column != -1 && row != -1) {
        RLMClazzProperty *propertyNode = self.parentWindowController.modelDocument.selectedObjectNode.propertyColumns[column];
        
        if (propertyNode.type == RLMPropertyTypeObject) {
            RLMObject *selectedInstance = [self.parentWindowController.modelDocument.selectedObjectNode instanceAtIndex:row];
            NSObject *propertyValue = selectedInstance[propertyNode.name];
            
            if ([propertyValue isKindOfClass:[RLMObject class]]) {
                RLMObject *linkedObject = (RLMObject *)propertyValue;
                RLMObjectSchema *linkedObjectSchema = linkedObject.schema;
                
                for (RLMClazzNode *clazzNode in self.parentWindowController.modelDocument.presentedRealm.topLevelClazzes) {
                    if ([clazzNode.name isEqualToString:linkedObjectSchema.className]) {
                        NSInteger index = [self.parentWindowController.outlineViewController.classesOutlineView rowForItem:clazzNode];
                        
                        [self.parentWindowController.outlineViewController.classesOutlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:index]
                                                                   byExtendingSelection:NO];
                        
                        [self updateTableView];
                        
                        // Right now we just fetches the object index from the proxy object.
                        // However, this must be changed later when the proxy object is made public
                        // and provides some mean to retrieve the underlying RLMObject object.
                        // Note: This selection of the linked object does not take any future row
                        // sorting into account!!!
                        NSNumber *indexNumber = [linkedObject valueForKeyPath:@"objectIndex"];
                        NSUInteger instanceIndex = indexNumber.integerValue;
                        
                        if (instanceIndex != NSNotFound) {
                            [self.instancesTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:instanceIndex]
                                                 byExtendingSelection:NO];
                        }
                        else {
                            [self.instancesTableView selectRowIndexes:nil
                                                 byExtendingSelection:NO];
                        }
                        
                        break;
                    }
                }
            }
        }
        else if (propertyNode.type == RLMPropertyTypeArray) {
            RLMObject *selectedInstance = [self.parentWindowController.modelDocument.selectedObjectNode instanceAtIndex:row];
            NSObject *propertyValue = selectedInstance[propertyNode.name];
            
            if ([propertyValue isKindOfClass:[RLMArray class]]) {
                RLMArray *linkedArray = (RLMArray *)propertyValue;
                
                RLMClazzNode *selectedClassNode = (RLMClazzNode *)self.parentWindowController.modelDocument.selectedObjectNode;
                
                RLMArrayNode *arrayNode = [selectedClassNode displayChildArray:linkedArray
                                                                  fromProperty:propertyNode.property
                                                                        object:selectedInstance];
/*
                [self.outlineViewController.classesOutlineView reloadData];
                
                [self.outlineViewController.classesOutlineView expandItem:selectedClassNode];
                NSInteger index = [self.outlineViewController.classesOutlineView rowForItem:arrayNode];
                if (index != NSNotFound) {
                    [self.outlineViewController.classesOutlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:index]
                                                               byExtendingSelection:NO];
                }
*/                
            }
        }
    }
}

- (void)updateTableView
{
    [self.instancesTableView reloadData];
    for(NSTableColumn *column in self.instancesTableView.tableColumns) {
        [column resizeToFitContents];
    }
}

#pragma mark - Private methods - Table view construction

- (void)updateSelectedObjectNode:(RLMObjectNode *)outlineNode
{
    self.parentWindowController.modelDocument.selectedObjectNode = outlineNode;
    
    // How many properties does the clazz contains?
    NSArray *columns = outlineNode.propertyColumns;
    NSUInteger columnCount = columns.count;
    
    // We clear the table view from all old columns
    NSUInteger existingColumnsCount = self.instancesTableView.numberOfColumns;
    for (NSUInteger index = 0; index < existingColumnsCount; index++) {
        NSTableColumn *column = [self.instancesTableView.tableColumns lastObject];
        [self.instancesTableView removeTableColumn:column];
    }
    
    // ... and add new columns matching the structure of the new realm table.
    for (NSUInteger index = 0; index < columnCount; index++) {
        NSTableColumn *tableColumn = [[NSTableColumn alloc] initWithIdentifier:[NSString stringWithFormat:@"Column #%lu", existingColumnsCount + index]];
        
        [self.instancesTableView addTableColumn:tableColumn];
    }
    
    // Set the column names and cell type / formatting
    for (NSUInteger index = 0; index < columns.count; index++) {
        NSTableColumn *tableColumn = self.instancesTableView.tableColumns[index];
        
        RLMClazzProperty *property = columns[index];
        NSString *columnName = property.name;
        
        switch (property.type) {
            case RLMPropertyTypeBool: {
                [self initializeSwitchButtonTableColumn:tableColumn
                                               withName:columnName
                                              alignment:NSRightTextAlignment
                                               editable:YES
                                                toolTip:@"Boolean"];
                break;
            }
                
            case RLMPropertyTypeInt: {
                [self initializeTableColumn:tableColumn
                                   withName:columnName
                                  alignment:NSRightTextAlignment
                                   editable:YES
                                    toolTip:@"Integer"];
                break;
                
            }
                
            case RLMPropertyTypeFloat: {
                [self initializeTableColumn:tableColumn
                                   withName:columnName
                                  alignment:NSRightTextAlignment
                                   editable:YES
                                    toolTip:@"Float"];
                break;
            }
                
            case RLMPropertyTypeDouble: {
                [self initializeTableColumn:tableColumn
                                   withName:columnName
                                  alignment:NSRightTextAlignment
                                   editable:YES
                                    toolTip:@"Double"];
                break;
            }
                
            case RLMPropertyTypeString: {
                [self initializeTableColumn:tableColumn
                                   withName:columnName
                                  alignment:NSLeftTextAlignment
                                   editable:YES
                                    toolTip:@"String"];
                break;
            }
                
            case RLMPropertyTypeData: {
                [self initializeTableColumn:tableColumn
                                   withName:columnName
                                  alignment:NSLeftTextAlignment
                                   editable:NO
                                    toolTip:@"Data"];
                break;
            }
                
            case RLMPropertyTypeAny: {
                [self initializeTableColumn:tableColumn
                                   withName:columnName
                                  alignment:NSLeftTextAlignment
                                   editable:NO
                                    toolTip:@"Any"];
                break;
            }
                
            case RLMPropertyTypeDate: {
                [self initializeTableColumn:tableColumn
                                   withName:columnName
                                  alignment:NSLeftTextAlignment
                                   editable:YES
                                    toolTip:@"Date"];
                break;
            }
                
            case RLMPropertyTypeArray: {
                [self initializeTableColumn:tableColumn
                                   withName:columnName
                                  alignment:NSLeftTextAlignment
                                   editable:NO
                                    toolTip:@"Array"];
                break;
            }
                
            case RLMPropertyTypeObject: {
                [self initializeTableColumn:tableColumn
                                   withName:columnName
                                  alignment:NSLeftTextAlignment
                                   editable:NO
                                    toolTip:@"Link to object"];
                break;
            }
        }
        
        
    }
    
    [self updateTableView];
}

- (NSCell *)initializeTableColumn:(NSTableColumn *)column withName:(NSString *)name alignment:(NSTextAlignment)alignment editable:(BOOL)editable toolTip:(NSString *)toolTip
{
    NSCell *cell = [[NSCell alloc] initTextCell:@""];
    
    [self initializeTabelColumn:column
                       withCell:cell
                           name:name
                      alignment:alignment
                       editable:editable
                        toolTip:toolTip];
    
    return cell;
}

- (NSCell *)initializeSwitchButtonTableColumn:(NSTableColumn *)column withName:(NSString *)name alignment:(NSTextAlignment)alignment editable:(BOOL)editable toolTip:(NSString *)toolTip
{
    NSButtonCell *cell = [[NSButtonCell alloc] init];
    
    cell.title = nil;
    cell.allowsMixedState = YES;
    cell.buttonType =NSSwitchButton;
    cell.alignment = NSCenterTextAlignment;
    cell.imagePosition = NSImageOnly;
    cell.controlSize = NSSmallControlSize;
    
    [self initializeTabelColumn:column
                       withCell:cell
                           name:name
                      alignment:alignment
                       editable:editable
                        toolTip:toolTip];
    
    return cell;
}

- (void)initializeTabelColumn:(NSTableColumn *)column withCell:(NSCell *)cell name:(NSString *) name alignment:(NSTextAlignment)alignment editable:(BOOL)editable toolTip:(NSString *)toolTip
{
    cell.alignment = alignment;
    cell.editable = editable;
    
    column.dataCell = cell;
    column.headerToolTip = toolTip;
    
    NSTableHeaderCell *headerCell = column.headerCell;
    headerCell.stringValue = name;
}


@end