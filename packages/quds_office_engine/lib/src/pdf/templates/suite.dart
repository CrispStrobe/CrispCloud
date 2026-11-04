/// Classified suite of customizable report templates.
library;

import 'dart:typed_data';

import '../../builders/office_markup.dart';
import '../../fonts/sfnt_parser.dart';
import '../widgets/pw_types.dart';
import 'kit.dart';
import 'sheets.dart';

const SheetLabels purchaseOrderTemplateLabels = SheetLabels(
      document: 'Purchase order',
      from: 'Buyer',
      to: 'Supplier',
      number: 'PO',
      date: 'Date',
      extra: 'Needed by',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Qty',
        'Unit',
        'Amount',
      ],
    );

const SheetLabels salesOrderTemplateLabels = SheetLabels(
      document: 'Sales order',
      from: 'Seller',
      to: 'Buyer',
      number: 'Order',
      date: 'Date',
      extra: 'Ship by',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Qty',
        'Amount',
      ],
    );

const SheetLabels creditNoteTemplateLabels = SheetLabels(
      document: 'Credit note',
      from: 'Issuer',
      to: 'Account',
      number: 'Credit',
      date: 'Date',
      extra: 'Invoice',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Reason',
        'Qty',
        'Credit',
      ],
    );

const SheetLabels debitNoteTemplateLabels = SheetLabels(
      document: 'Debit note',
      from: 'Issuer',
      to: 'Account',
      number: 'Debit',
      date: 'Date',
      extra: 'Invoice',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Reason',
        'Qty',
        'Charge',
      ],
    );

const SheetLabels proformaTemplateLabels = SheetLabels(
      document: 'Proforma invoice',
      from: 'Seller',
      to: 'Buyer',
      number: 'Proforma',
      date: 'Date',
      extra: 'Valid until',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Qty',
        'Amount',
      ],
    );

const SheetLabels serviceEstimateTemplateLabels = SheetLabels(
      document: 'Service estimate',
      from: 'Workshop',
      to: 'Client',
      number: 'Estimate',
      date: 'Date',
      extra: 'Valid until',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Task',
        'Hours',
        'Amount',
      ],
    );

const SheetLabels commissionNoteTemplateLabels = SheetLabels(
      document: 'Commission note',
      from: 'House',
      to: 'Agent',
      number: 'Note',
      date: 'Date',
      extra: 'Period',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Deal',
        'Base',
        'Rate',
        'Commission',
      ],
    );

const SheetLabels billOfLadingTemplateLabels = SheetLabels(
      document: 'Bill of lading',
      from: 'Shipper',
      to: 'Consignee',
      number: 'B/L',
      date: 'Date',
      extra: 'Vessel',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Marks',
        'Qty',
        'Weight',
        'Goods',
      ],
    );

const SheetLabels freightQuoteTemplateLabels = SheetLabels(
      document: 'Freight quote',
      from: 'Carrier',
      to: 'Shipper',
      number: 'Quote',
      date: 'Date',
      extra: 'Lane',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Leg',
        'Weight',
        'Amount',
      ],
    );

const SheetLabels feeReceiptTemplateLabels = SheetLabels(
      document: 'Fee receipt',
      from: 'School',
      to: 'Payer',
      number: 'Receipt',
      date: 'Date',
      extra: 'Term',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Fee',
        'Detail',
        'Amount',
      ],
    );

const SheetLabels rentReceiptTemplateLabels = SheetLabels(
      document: 'Rent receipt',
      from: 'Landlord',
      to: 'Tenant',
      number: 'Receipt',
      date: 'Date',
      extra: 'Month',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Charge',
        'Period',
        'Amount',
      ],
    );

const SheetLabels donationReceiptTemplateLabels = SheetLabels(
      document: 'Donation receipt',
      from: 'Fund',
      to: 'Donor',
      number: 'Receipt',
      date: 'Date',
      extra: 'Fund',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Gift',
        'Detail',
        'Amount',
      ],
    );

const SheetLabels paymentVoucherTemplateLabels = SheetLabels(
      document: 'Payment voucher',
      from: 'Payer',
      to: 'Payee',
      number: 'Voucher',
      date: 'Date',
      extra: 'Method',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Purpose',
        'Ref',
        'Amount',
      ],
    );

const SheetLabels receiptVoucherTemplateLabels = SheetLabels(
      document: 'Receipt voucher',
      from: 'Receiver',
      to: 'Payer',
      number: 'Voucher',
      date: 'Date',
      extra: 'Method',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Purpose',
        'Ref',
        'Amount',
      ],
    );

const SheetLabels packingListTemplateLabels = SheetLabels(
      document: 'Packing list',
      from: 'Packer',
      to: 'Receiver',
      number: 'List',
      date: 'Date',
      extra: 'Crates',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Ordered',
        'Packed',
      ],
    );

const SheetLabels priceListTemplateLabels = SheetLabels(
      document: 'Price list',
      from: 'Seller',
      to: 'Market',
      number: 'List',
      date: 'Date',
      extra: 'Valid until',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'SKU',
        'Item',
        'Unit',
        'Price',
      ],
    );

const SheetLabels goodsReceivedTemplateLabels = SheetLabels(
      document: 'Goods received',
      from: 'Receiver',
      to: 'Supplier',
      number: 'GRN',
      date: 'Date',
      extra: 'PO',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Ordered',
        'Received',
      ],
    );

const SheetLabels returnAuthorizationTemplateLabels = SheetLabels(
      document: 'Return authorization',
      from: 'Seller',
      to: 'Buyer',
      number: 'RMA',
      date: 'Date',
      extra: 'Invoice',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Qty',
        'Reason',
      ],
    );

const SheetLabels consignmentNoteTemplateLabels = SheetLabels(
      document: 'Consignment note',
      from: 'Holder',
      to: 'Owner',
      number: 'Note',
      date: 'Date',
      extra: 'Hold until',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Qty',
        'Condition',
      ],
    );

const SheetLabels goodsIssueTemplateLabels = SheetLabels(
      document: 'Goods issue',
      from: 'Store',
      to: 'Requester',
      number: 'Issue',
      date: 'Date',
      extra: 'Cost centre',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Qty',
        'Bin',
      ],
    );

const SheetLabels inventoryCountTemplateLabels = SheetLabels(
      document: 'Inventory count',
      from: 'Counter',
      to: 'Store',
      number: 'Count',
      date: 'Date',
      extra: 'Aisle',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Book',
        'Counted',
      ],
    );

const SheetLabels assetRegisterTemplateLabels = SheetLabels(
      document: 'Asset register',
      from: 'Registry',
      to: 'Site',
      number: 'Register',
      date: 'Date',
      extra: 'Site',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Tag',
        'Asset',
        'Holder',
      ],
    );

const SheetLabels visitorLogTemplateLabels = SheetLabels(
      document: 'Visitor log',
      from: 'Gate',
      to: 'Host',
      number: 'Log',
      date: 'Date',
      extra: 'Gate',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Name',
        'In',
        'Host',
      ],
    );

const SheetLabels shiftRosterTemplateLabels = SheetLabels(
      document: 'Shift roster',
      from: 'Planner',
      to: 'Team',
      number: 'Roster',
      date: 'Date',
      extra: 'Week',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Name',
        'Watch',
        'Role',
      ],
    );

const SheetLabels serviceTicketTemplateLabels = SheetLabels(
      document: 'Service ticket',
      from: 'Desk',
      to: 'Site',
      number: 'Ticket',
      date: 'Date',
      extra: 'Priority',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Task',
        'Owner',
        'Status',
      ],
    );

const SheetLabels pickListTemplateLabels = SheetLabels(
      document: 'Pick list',
      from: 'Warehouse',
      to: 'Order',
      number: 'Pick',
      date: 'Date',
      extra: 'Bay',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Bin',
        'Item',
        'Qty',
      ],
    );

const SheetLabels deliveryManifestTemplateLabels = SheetLabels(
      document: 'Delivery manifest',
      from: 'Dispatcher',
      to: 'Driver',
      number: 'Run',
      date: 'Date',
      extra: 'Vehicle',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Stop',
        'Place',
        'Crates',
      ],
    );

const SheetLabels waybillTemplateLabels = SheetLabels(
      document: 'Waybill',
      from: 'Origin',
      to: 'Destination',
      number: 'Waybill',
      date: 'Date',
      extra: 'Driver',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Qty',
        'Marks',
      ],
    );

const SheetLabels warehouseTransferTemplateLabels = SheetLabels(
      document: 'Warehouse transfer',
      from: 'From store',
      to: 'To store',
      number: 'Transfer',
      date: 'Date',
      extra: 'Reason',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Qty',
        'From bin',
      ],
    );

const SheetLabels loadSheetTemplateLabels = SheetLabels(
      document: 'Load sheet',
      from: 'Bay',
      to: 'Vehicle',
      number: 'Load',
      date: 'Date',
      extra: 'Door',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Order',
        'Item',
        'Qty',
      ],
    );

const SheetLabels shippingNoticeTemplateLabels = SheetLabels(
      document: 'Shipping notice',
      from: 'Sender',
      to: 'Receiver',
      number: 'Notice',
      date: 'Date',
      extra: 'ETA',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Qty',
        'Marks',
      ],
    );

const SheetLabels attendanceSheetTemplateLabels = SheetLabels(
      document: 'Attendance sheet',
      from: 'Team',
      to: 'Shift',
      number: 'Sheet',
      date: 'Date',
      extra: 'Shift',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Name',
        'In',
        'Mark',
      ],
    );

const SheetLabels classRegisterTemplateLabels = SheetLabels(
      document: 'Class register',
      from: 'Class',
      to: 'Teacher',
      number: 'Register',
      date: 'Date',
      extra: 'Class',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Name',
        'Mark',
        'Note',
      ],
    );

const SheetLabels transcriptTemplateLabels = SheetLabels(
      document: 'Transcript',
      from: 'School',
      to: 'Student',
      number: 'Record',
      date: 'Date',
      extra: 'Year',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Subject',
        'Mark',
        'Grade',
      ],
    );

const SheetLabels reportCardTemplateLabels = SheetLabels(
      document: 'Report card',
      from: 'School',
      to: 'Student',
      number: 'Card',
      date: 'Date',
      extra: 'Term',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Subject',
        'Mark',
        'Comment',
      ],
    );

const SheetLabels propertyListingTemplateLabels = SheetLabels(
      document: 'Property listing',
      from: 'Office',
      to: 'Area',
      number: 'List',
      date: 'Date',
      extra: 'Area',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Unit',
        'Rent',
        'Status',
      ],
    );

const SheetLabels beneficiaryListTemplateLabels = SheetLabels(
      document: 'Beneficiary list',
      from: 'Program',
      to: 'Site',
      number: 'List',
      date: 'Date',
      extra: 'Round',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Name',
        'Share',
        'Mark',
      ],
    );

const SheetLabels fieldDistributionTemplateLabels = SheetLabels(
      document: 'Distribution sheet',
      from: 'Team',
      to: 'Round',
      number: 'Sheet',
      date: 'Date',
      extra: 'Site',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Household',
        'Item',
        'Qty',
      ],
    );

const SheetLabels workshopRegisterTemplateLabels = SheetLabels(
      document: 'Workshop register',
      from: 'Host',
      to: 'Session',
      number: 'Session',
      date: 'Date',
      extra: 'Room',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Name',
        'Role',
        'Mark',
      ],
    );

const SheetLabels volunteerHoursTemplateLabels = SheetLabels(
      document: 'Volunteer hours',
      from: 'Program',
      to: 'Period',
      number: 'Sheet',
      date: 'Date',
      extra: 'Period',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Name',
        'Hours',
        'Task',
      ],
    );

const SheetLabels timesheetTemplateLabels = SheetLabels(
      document: 'Timesheet',
      from: 'Worker',
      to: 'Period',
      number: 'Sheet',
      date: 'Date',
      extra: 'Week',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Day',
        'Hours',
        'Project',
      ],
    );

const SheetLabels milestoneTrackerTemplateLabels = SheetLabels(
      document: 'Milestone tracker',
      from: 'Project',
      to: 'Owner',
      number: 'Tracker',
      date: 'Date',
      extra: 'Phase',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Milestone',
        'Due',
        'Status',
      ],
    );

const SheetLabels riskRegisterTemplateLabels = SheetLabels(
      document: 'Risk register',
      from: 'Project',
      to: 'Review',
      number: 'Register',
      date: 'Date',
      extra: 'Review',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Risk',
        'Owner',
        'Rating',
      ],
    );

const SheetLabels issueLogTemplateLabels = SheetLabels(
      document: 'Issue log',
      from: 'Desk',
      to: 'Week',
      number: 'Log',
      date: 'Date',
      extra: 'Week',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Issue',
        'Owner',
        'Status',
      ],
    );

const SheetLabels comparisonTemplateLabels = SheetLabels(
      document: 'Comparison',
      from: 'Author',
      to: 'Choice',
      number: 'Note',
      date: 'Date',
      extra: 'Choice',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Point',
        'Crate',
        'Chest',
      ],
    );

const SheetLabels leaderboardTemplateLabels = SheetLabels(
      document: 'Leaderboard',
      from: 'Board',
      to: 'Period',
      number: 'Board',
      date: 'Date',
      extra: 'Period',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Rank',
        'Name',
        'Score',
      ],
    );

const SheetLabels exceptionReportTemplateLabels = SheetLabels(
      document: 'Exception report',
      from: 'Desk',
      to: 'Rule',
      number: 'Report',
      date: 'Date',
      extra: 'Rule',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Case',
        'Expected',
        'Actual',
      ],
    );

const SheetLabels profitAndLossTemplateLabels = SheetLabels(
      document: 'Profit and loss',
      from: 'Entity',
      to: 'Period',
      number: 'Statement',
      date: 'Date',
      extra: 'Period',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Line',
        'Kind',
        'Amount',
      ],
    );

const SheetLabels balanceSnapshotTemplateLabels = SheetLabels(
      document: 'Balance snapshot',
      from: 'Entity',
      to: 'As of',
      number: 'Snapshot',
      date: 'Date',
      extra: 'As of',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Line',
        'Side',
        'Amount',
      ],
    );

const SheetLabels cashFlowTemplateLabels = SheetLabels(
      document: 'Cash flow',
      from: 'Entity',
      to: 'Period',
      number: 'Flow',
      date: 'Date',
      extra: 'Period',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Line',
        'Way',
        'Amount',
      ],
    );

const SheetLabels budgetActualTemplateLabels = SheetLabels(
      document: 'Budget versus actual',
      from: 'Entity',
      to: 'Period',
      number: 'Sheet',
      date: 'Date',
      extra: 'Period',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Line',
        'Plan',
        'Actual',
        'Variance',
      ],
    );

const SheetLabels agedReceivablesTemplateLabels = SheetLabels(
      document: 'Aged receivables',
      from: 'Entity',
      to: 'As of',
      number: 'Aging',
      date: 'Date',
      extra: 'As of',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Account',
        'Current',
        '30 days',
        '60 days',
      ],
    );

const SheetLabels agedPayablesTemplateLabels = SheetLabels(
      document: 'Aged payables',
      from: 'Entity',
      to: 'As of',
      number: 'Aging',
      date: 'Date',
      extra: 'As of',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Supplier',
        'Current',
        '30 days',
        '60 days',
      ],
    );

const SheetLabels journalTemplateLabels = SheetLabels(
      document: 'Journal',
      from: 'Book',
      to: 'Day',
      number: 'Entry',
      date: 'Date',
      extra: 'Day',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Account',
        'Detail',
        'Debit',
        'Credit',
      ],
    );

const SheetLabels pettyCashTemplateLabels = SheetLabels(
      document: 'Petty cash',
      from: 'Custodian',
      to: 'Box',
      number: 'Book',
      date: 'Date',
      extra: 'Box',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Date',
        'Detail',
        'Out',
        'Balance',
      ],
    );

const SheetLabels loanScheduleTemplateLabels = SheetLabels(
      document: 'Loan schedule',
      from: 'Lender',
      to: 'Borrower',
      number: 'Loan',
      date: 'Date',
      extra: 'Rate note',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Due',
        'Principal',
        'Charge',
        'Balance',
      ],
    );

const SheetLabels bankReconciliationTemplateLabels = SheetLabels(
      document: 'Bank reconciliation',
      from: 'Book',
      to: 'Bank',
      number: 'Reconcile',
      date: 'Date',
      extra: 'As of',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Book',
        'Bank',
      ],
    );

const SheetLabels taxSummaryTemplateLabels = SheetLabels(
      document: 'Tax summary',
      from: 'Entity',
      to: 'Period',
      number: 'Summary',
      date: 'Date',
      extra: 'Period',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Bucket',
        'Base',
        'Tax',
      ],
    );

const SheetLabels payrollSummaryTemplateLabels = SheetLabels(
      document: 'Payroll summary',
      from: 'Employer',
      to: 'Period',
      number: 'Run',
      date: 'Date',
      extra: 'Period',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Band',
        'Headcount',
        'Net',
      ],
    );

const SheetLabels tenantStatementTemplateLabels = SheetLabels(
      document: 'Tenant statement',
      from: 'Office',
      to: 'Tenant',
      number: 'Unit',
      date: 'Date',
      extra: 'Month',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Date',
        'Detail',
        'Charge',
        'Paid',
      ],
    );

const SheetLabels offerLetterTemplateLabels = SheetLabels(
      document: 'Offer letter',
      from: 'Employer',
      to: 'Candidate',
      number: 'Offer',
      date: 'Date',
      extra: 'Start',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Detail',
        'Amount',
      ],
    );

const SheetLabels appointmentLetterTemplateLabels = SheetLabels(
      document: 'Appointment letter',
      from: 'Employer',
      to: 'Employee',
      number: 'Letter',
      date: 'Date',
      extra: 'Post',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Detail',
        'Amount',
      ],
    );

const SheetLabels experienceLetterTemplateLabels = SheetLabels(
      document: 'Experience letter',
      from: 'Employer',
      to: 'To whom',
      number: 'Letter',
      date: 'Date',
      extra: 'Served',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Detail',
        'Amount',
      ],
    );

const SheetLabels warningNoticeTemplateLabels = SheetLabels(
      document: 'Warning notice',
      from: 'Manager',
      to: 'Employee',
      number: 'Notice',
      date: 'Date',
      extra: 'Level',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Detail',
        'Amount',
      ],
    );

const SheetLabels recommendationLetterTemplateLabels = SheetLabels(
      document: 'Recommendation',
      from: 'Writer',
      to: 'Reader',
      number: 'Letter',
      date: 'Date',
      extra: 'About',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Detail',
        'Amount',
      ],
    );

const SheetLabels leaveRequestTemplateLabels = SheetLabels(
      document: 'Leave request',
      from: 'Employee',
      to: 'Manager',
      number: 'Request',
      date: 'Date',
      extra: 'Days',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Detail',
        'Amount',
      ],
    );

const SheetLabels welcomeNoteTemplateLabels = SheetLabels(
      document: 'Welcome note',
      from: 'Host',
      to: 'Newcomer',
      number: 'Note',
      date: 'Date',
      extra: 'Desk',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Detail',
        'Amount',
      ],
    );

const SheetLabels relievingLetterTemplateLabels = SheetLabels(
      document: 'Relieving letter',
      from: 'Employer',
      to: 'Employee',
      number: 'Letter',
      date: 'Date',
      extra: 'Last day',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Detail',
        'Amount',
      ],
    );

const SheetLabels referenceLetterTemplateLabels = SheetLabels(
      document: 'Reference letter',
      from: 'House',
      to: 'Reader',
      number: 'Letter',
      date: 'Date',
      extra: 'About',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Detail',
        'Amount',
      ],
    );

const SheetLabels admissionLetterTemplateLabels = SheetLabels(
      document: 'Admission letter',
      from: 'School',
      to: 'Student',
      number: 'Offer',
      date: 'Date',
      extra: 'Start',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Detail',
        'Amount',
      ],
    );

const SheetLabels announcementTemplateLabels = SheetLabels(
      document: 'Announcement',
      from: 'From',
      to: 'Audience',
      number: 'Notice',
      date: 'Date',
      extra: 'Effective',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Detail',
        'Amount',
      ],
    );

const SheetLabels meetingNoticeTemplateLabels = SheetLabels(
      document: 'Meeting notice',
      from: 'Caller',
      to: 'Invited',
      number: 'Notice',
      date: 'Date',
      extra: 'Room',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Detail',
        'Amount',
      ],
    );

const SheetLabels decisionNoteTemplateLabels = SheetLabels(
      document: 'Decision note',
      from: 'Decider',
      to: 'Audience',
      number: 'Decision',
      date: 'Date',
      extra: 'Effective',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Detail',
        'Amount',
      ],
    );

const SheetLabels internshipCertificateTemplateLabels = SheetLabels(
      document: 'Internship certificate',
      from: 'Issuer',
      to: 'To',
      number: 'Certificate',
      date: 'Date',
      extra: 'Hours',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Detail',
        'Amount',
      ],
    );

const SheetLabels pressReleaseTemplateLabels = SheetLabels(
      document: 'Press release',
      from: 'From',
      to: 'To',
      number: 'Release',
      date: 'Date',
      extra: 'Embargo',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Detail',
        'Amount',
      ],
    );

const SheetLabels projectStatusTemplateLabels = SheetLabels(
      document: 'Project status',
      from: 'From',
      to: 'To',
      number: 'Status',
      date: 'Date',
      extra: 'Phase',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Detail',
        'Amount',
      ],
    );

const SheetLabels policyNoteTemplateLabels = SheetLabels(
      document: 'Policy note',
      from: 'From',
      to: 'To',
      number: 'Policy',
      date: 'Date',
      extra: 'Binds',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Detail',
        'Amount',
      ],
    );

const SheetLabels executiveSummaryTemplateLabels = SheetLabels(
      document: 'Executive summary',
      from: 'From',
      to: 'To',
      number: 'Brief',
      date: 'Date',
      extra: 'For',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Detail',
        'Amount',
      ],
    );

const SheetLabels afterActionTemplateLabels = SheetLabels(
      document: 'After-action review',
      from: 'From',
      to: 'To',
      number: 'Review',
      date: 'Date',
      extra: 'Event',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Detail',
        'Amount',
      ],
    );

const SheetLabels newsletterTemplateLabels = SheetLabels(
      document: 'Newsletter',
      from: 'From',
      to: 'To',
      number: 'Issue',
      date: 'Date',
      extra: 'Month',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Detail',
        'Amount',
      ],
    );

const SheetLabels proposalTemplateLabels = SheetLabels(
      document: 'Proposal',
      from: 'From',
      to: 'To',
      number: 'Proposal',
      date: 'Date',
      extra: 'Ask',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Detail',
        'Amount',
      ],
    );

const SheetLabels safetyBriefingTemplateLabels = SheetLabels(
      document: 'Safety briefing',
      from: 'From',
      to: 'To',
      number: 'Brief',
      date: 'Date',
      extra: 'Watch',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Detail',
        'Amount',
      ],
    );

const SheetLabels incidentReportTemplateLabels = SheetLabels(
      document: 'Incident report',
      from: 'From',
      to: 'To',
      number: 'Report',
      date: 'Date',
      extra: 'Place',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Detail',
        'Amount',
      ],
    );

const SheetLabels handoverNoteTemplateLabels = SheetLabels(
      document: 'Handover',
      from: 'From watch',
      to: 'To watch',
      number: 'Handover',
      date: 'Date',
      extra: 'Open items',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Detail',
        'Amount',
      ],
    );

const SheetLabels changeRequestTemplateLabels = SheetLabels(
      document: 'Change request',
      from: 'From',
      to: 'To',
      number: 'Request',
      date: 'Date',
      extra: 'Window',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Detail',
        'Amount',
      ],
    );

const SheetLabels syllabusTemplateLabels = SheetLabels(
      document: 'Syllabus',
      from: 'From',
      to: 'To',
      number: 'Course',
      date: 'Date',
      extra: 'Term',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Detail',
        'Amount',
      ],
    );

const SheetLabels assignmentBriefTemplateLabels = SheetLabels(
      document: 'Assignment brief',
      from: 'From',
      to: 'To',
      number: 'Task',
      date: 'Date',
      extra: 'Due',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Detail',
        'Amount',
      ],
    );

const SheetLabels progressReportTemplateLabels = SheetLabels(
      document: 'Progress report',
      from: 'School',
      to: 'Student',
      number: 'Report',
      date: 'Date',
      extra: 'Term',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Detail',
        'Amount',
      ],
    );

const SheetLabels leaseSummaryTemplateLabels = SheetLabels(
      document: 'Lease summary',
      from: 'Office',
      to: 'Tenant',
      number: 'Unit',
      date: 'Date',
      extra: 'Term',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Detail',
        'Amount',
      ],
    );

const SheetLabels grantReportTemplateLabels = SheetLabels(
      document: 'Grant report',
      from: 'From',
      to: 'To',
      number: 'Grant',
      date: 'Date',
      extra: 'Period',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Detail',
        'Amount',
      ],
    );

const SheetLabels programBriefTemplateLabels = SheetLabels(
      document: 'Program brief',
      from: 'From',
      to: 'To',
      number: 'Brief',
      date: 'Date',
      extra: 'Week',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Detail',
        'Amount',
      ],
    );

const SheetLabels workPermitTemplateLabels = SheetLabels(
      document: 'Work permit',
      from: 'From',
      to: 'To',
      number: 'Permit',
      date: 'Date',
      extra: 'Job',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Mark',
        'Note',
      ],
    );

const SheetLabels auditFindingsTemplateLabels = SheetLabels(
      document: 'Audit findings',
      from: 'From',
      to: 'To',
      number: 'Audit',
      date: 'Date',
      extra: 'Site',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Mark',
        'Note',
      ],
    );

const SheetLabels moveInChecklistTemplateLabels = SheetLabels(
      document: 'Move-in checklist',
      from: 'From',
      to: 'To',
      number: 'Unit',
      date: 'Date',
      extra: 'Tenant',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Mark',
        'Note',
      ],
    );

const SheetLabels maintenanceRequestTemplateLabels = SheetLabels(
      document: 'Maintenance request',
      from: 'From',
      to: 'To',
      number: 'Request',
      date: 'Date',
      extra: 'Unit',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Mark',
        'Note',
      ],
    );

const SheetLabels scorecardTemplateLabels = SheetLabels(
      document: 'Scorecard',
      from: 'From',
      to: 'To',
      number: 'Card',
      date: 'Date',
      extra: 'Period',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Detail',
        'Amount',
      ],
    );

const SheetLabels surveyResultsTemplateLabels = SheetLabels(
      document: 'Survey results',
      from: 'From',
      to: 'To',
      number: 'Survey',
      date: 'Date',
      extra: 'n',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Detail',
        'Amount',
      ],
    );

const SheetLabels capacityReportTemplateLabels = SheetLabels(
      document: 'Capacity report',
      from: 'From',
      to: 'To',
      number: 'Report',
      date: 'Date',
      extra: 'Day',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Detail',
        'Amount',
      ],
    );

const SheetLabels impactSheetTemplateLabels = SheetLabels(
      document: 'Impact sheet',
      from: 'From',
      to: 'To',
      number: 'Sheet',
      date: 'Date',
      extra: 'Period',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Detail',
        'Amount',
      ],
    );

const SheetLabels dailySiteReportTemplateLabels = SheetLabels(
      document: 'Daily site report',
      from: 'From',
      to: 'To',
      number: 'Day',
      date: 'Date',
      extra: 'Shift',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Detail',
        'Amount',
      ],
    );

const SheetLabels employeeProfileTemplateLabels = SheetLabels(
      document: 'Employee profile',
      from: 'From',
      to: 'To',
      number: 'File',
      date: 'Date',
      extra: 'Post',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Detail',
        'Amount',
      ],
    );

const SheetLabels maintenanceLogTemplateLabels = SheetLabels(
      document: 'Maintenance log',
      from: 'From',
      to: 'To',
      number: 'Log',
      date: 'Date',
      extra: 'Week',
      subject: 'Subject',
      notes: 'Notes',
      subtotal: 'Subtotal',
      tax: 'Tax',
      total: 'Total',
      presentedTo: 'Presented to',
      columns: <String>[
        'Item',
        'Detail',
        'Amount',
      ],
    );

/// Purchase order.
class PurchaseOrderTemplate implements SuiteSheet {
  /// PurchaseOrderTemplate API.
  PurchaseOrderTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.commerce,
        labels = labels ?? purchaseOrderTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.trade,
          direction: direction,
          theme: theme ?? TemplateThemes.commerce,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? purchaseOrderTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.invoice,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Sales order.
class SalesOrderTemplate implements SuiteSheet {
  /// SalesOrderTemplate API.
  SalesOrderTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.commerce,
        labels = labels ?? salesOrderTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.trade,
          direction: direction,
          theme: theme ?? TemplateThemes.commerce,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? salesOrderTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.invoice,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Credit note.
class CreditNoteTemplate implements SuiteSheet {
  /// CreditNoteTemplate API.
  CreditNoteTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.commerce,
        labels = labels ?? creditNoteTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.trade,
          direction: direction,
          theme: theme ?? TemplateThemes.commerce,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? creditNoteTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.invoice,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Debit note.
class DebitNoteTemplate implements SuiteSheet {
  /// DebitNoteTemplate API.
  DebitNoteTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.commerce,
        labels = labels ?? debitNoteTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.trade,
          direction: direction,
          theme: theme ?? TemplateThemes.commerce,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? debitNoteTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.invoice,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Proforma invoice.
class ProformaTemplate implements SuiteSheet {
  /// ProformaTemplate API.
  ProformaTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.commerce,
        labels = labels ?? proformaTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.trade,
          direction: direction,
          theme: theme ?? TemplateThemes.commerce,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? proformaTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.quote,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Service estimate.
class ServiceEstimateTemplate implements SuiteSheet {
  /// ServiceEstimateTemplate API.
  ServiceEstimateTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.commerce,
        labels = labels ?? serviceEstimateTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.trade,
          direction: direction,
          theme: theme ?? TemplateThemes.commerce,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? serviceEstimateTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.quote,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Commission note.
class CommissionNoteTemplate implements SuiteSheet {
  /// CommissionNoteTemplate API.
  CommissionNoteTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.commerce,
        labels = labels ?? commissionNoteTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.trade,
          direction: direction,
          theme: theme ?? TemplateThemes.commerce,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? commissionNoteTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.invoice,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Bill of lading.
class BillOfLadingTemplate implements SuiteSheet {
  /// BillOfLadingTemplate API.
  BillOfLadingTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.logistics,
        labels = labels ?? billOfLadingTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.trade,
          direction: direction,
          theme: theme ?? TemplateThemes.logistics,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? billOfLadingTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.route,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Freight quote.
class FreightQuoteTemplate implements SuiteSheet {
  /// FreightQuoteTemplate API.
  FreightQuoteTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.logistics,
        labels = labels ?? freightQuoteTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.trade,
          direction: direction,
          theme: theme ?? TemplateThemes.logistics,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? freightQuoteTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.quote,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Fee receipt.
class FeeReceiptTemplate implements SuiteSheet {
  /// FeeReceiptTemplate API.
  FeeReceiptTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.education,
        labels = labels ?? feeReceiptTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.trade,
          direction: direction,
          theme: theme ?? TemplateThemes.education,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? feeReceiptTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.voucher,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Rent receipt.
class RentReceiptTemplate implements SuiteSheet {
  /// RentReceiptTemplate API.
  RentReceiptTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.property,
        labels = labels ?? rentReceiptTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.trade,
          direction: direction,
          theme: theme ?? TemplateThemes.property,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? rentReceiptTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.voucher,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Donation receipt.
class DonationReceiptTemplate implements SuiteSheet {
  /// DonationReceiptTemplate API.
  DonationReceiptTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.programs,
        labels = labels ?? donationReceiptTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.trade,
          direction: direction,
          theme: theme ?? TemplateThemes.programs,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? donationReceiptTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.voucher,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Payment voucher.
class PaymentVoucherTemplate implements SuiteSheet {
  /// PaymentVoucherTemplate API.
  PaymentVoucherTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.finance,
        labels = labels ?? paymentVoucherTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.trade,
          direction: direction,
          theme: theme ?? TemplateThemes.finance,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? paymentVoucherTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.voucher,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Receipt voucher.
class ReceiptVoucherTemplate implements SuiteSheet {
  /// ReceiptVoucherTemplate API.
  ReceiptVoucherTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.finance,
        labels = labels ?? receiptVoucherTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.trade,
          direction: direction,
          theme: theme ?? TemplateThemes.finance,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? receiptVoucherTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.voucher,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Packing list.
class PackingListTemplate implements SuiteSheet {
  /// PackingListTemplate API.
  PackingListTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.commerce,
        labels = labels ?? packingListTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.listing,
          direction: direction,
          theme: theme ?? TemplateThemes.commerce,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? packingListTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.catalog,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Price list.
class PriceListTemplate implements SuiteSheet {
  /// PriceListTemplate API.
  PriceListTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.commerce,
        labels = labels ?? priceListTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.listing,
          direction: direction,
          theme: theme ?? TemplateThemes.commerce,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? priceListTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.catalog,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Goods received.
class GoodsReceivedTemplate implements SuiteSheet {
  /// GoodsReceivedTemplate API.
  GoodsReceivedTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.commerce,
        labels = labels ?? goodsReceivedTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.listing,
          direction: direction,
          theme: theme ?? TemplateThemes.commerce,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? goodsReceivedTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.catalog,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Return authorization.
class ReturnAuthorizationTemplate implements SuiteSheet {
  /// ReturnAuthorizationTemplate API.
  ReturnAuthorizationTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.commerce,
        labels = labels ?? returnAuthorizationTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.listing,
          direction: direction,
          theme: theme ?? TemplateThemes.commerce,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? returnAuthorizationTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.catalog,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Consignment note.
class ConsignmentNoteTemplate implements SuiteSheet {
  /// ConsignmentNoteTemplate API.
  ConsignmentNoteTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.commerce,
        labels = labels ?? consignmentNoteTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.listing,
          direction: direction,
          theme: theme ?? TemplateThemes.commerce,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? consignmentNoteTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.catalog,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Goods issue.
class GoodsIssueTemplate implements SuiteSheet {
  /// GoodsIssueTemplate API.
  GoodsIssueTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.operations,
        labels = labels ?? goodsIssueTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.listing,
          direction: direction,
          theme: theme ?? TemplateThemes.operations,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? goodsIssueTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.catalog,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Inventory count.
class InventoryCountTemplate implements SuiteSheet {
  /// InventoryCountTemplate API.
  InventoryCountTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.operations,
        labels = labels ?? inventoryCountTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.listing,
          direction: direction,
          theme: theme ?? TemplateThemes.operations,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? inventoryCountTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.catalog,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Asset register.
class AssetRegisterTemplate implements SuiteSheet {
  /// AssetRegisterTemplate API.
  AssetRegisterTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.operations,
        labels = labels ?? assetRegisterTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.listing,
          direction: direction,
          theme: theme ?? TemplateThemes.operations,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? assetRegisterTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.catalog,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Visitor log.
class VisitorLogTemplate implements SuiteSheet {
  /// VisitorLogTemplate API.
  VisitorLogTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.operations,
        labels = labels ?? visitorLogTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.listing,
          direction: direction,
          theme: theme ?? TemplateThemes.operations,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? visitorLogTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.timeline,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Shift roster.
class ShiftRosterTemplate implements SuiteSheet {
  /// ShiftRosterTemplate API.
  ShiftRosterTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.operations,
        labels = labels ?? shiftRosterTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.listing,
          direction: direction,
          theme: theme ?? TemplateThemes.operations,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? shiftRosterTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.timeline,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Service ticket.
class ServiceTicketTemplate implements SuiteSheet {
  /// ServiceTicketTemplate API.
  ServiceTicketTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.operations,
        labels = labels ?? serviceTicketTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.listing,
          direction: direction,
          theme: theme ?? TemplateThemes.operations,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? serviceTicketTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.catalog,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Pick list.
class PickListTemplate implements SuiteSheet {
  /// PickListTemplate API.
  PickListTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.logistics,
        labels = labels ?? pickListTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.listing,
          direction: direction,
          theme: theme ?? TemplateThemes.logistics,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? pickListTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.catalog,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Delivery manifest.
class DeliveryManifestTemplate implements SuiteSheet {
  /// DeliveryManifestTemplate API.
  DeliveryManifestTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.logistics,
        labels = labels ?? deliveryManifestTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.listing,
          direction: direction,
          theme: theme ?? TemplateThemes.logistics,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? deliveryManifestTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.route,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Waybill.
class WaybillTemplate implements SuiteSheet {
  /// WaybillTemplate API.
  WaybillTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.logistics,
        labels = labels ?? waybillTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.listing,
          direction: direction,
          theme: theme ?? TemplateThemes.logistics,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? waybillTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.route,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Warehouse transfer.
class WarehouseTransferTemplate implements SuiteSheet {
  /// WarehouseTransferTemplate API.
  WarehouseTransferTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.logistics,
        labels = labels ?? warehouseTransferTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.listing,
          direction: direction,
          theme: theme ?? TemplateThemes.logistics,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? warehouseTransferTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.route,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Load sheet.
class LoadSheetTemplate implements SuiteSheet {
  /// LoadSheetTemplate API.
  LoadSheetTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.logistics,
        labels = labels ?? loadSheetTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.listing,
          direction: direction,
          theme: theme ?? TemplateThemes.logistics,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? loadSheetTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.catalog,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Shipping notice.
class ShippingNoticeTemplate implements SuiteSheet {
  /// ShippingNoticeTemplate API.
  ShippingNoticeTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.logistics,
        labels = labels ?? shippingNoticeTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.listing,
          direction: direction,
          theme: theme ?? TemplateThemes.logistics,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? shippingNoticeTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.route,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Attendance sheet.
class AttendanceSheetTemplate implements SuiteSheet {
  /// AttendanceSheetTemplate API.
  AttendanceSheetTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.people,
        labels = labels ?? attendanceSheetTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.listing,
          direction: direction,
          theme: theme ?? TemplateThemes.people,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? attendanceSheetTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.checks,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Class register.
class ClassRegisterTemplate implements SuiteSheet {
  /// ClassRegisterTemplate API.
  ClassRegisterTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.education,
        labels = labels ?? classRegisterTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.listing,
          direction: direction,
          theme: theme ?? TemplateThemes.education,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? classRegisterTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.checks,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Transcript.
class TranscriptTemplate implements SuiteSheet {
  /// TranscriptTemplate API.
  TranscriptTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.education,
        labels = labels ?? transcriptTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.listing,
          direction: direction,
          theme: theme ?? TemplateThemes.education,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? transcriptTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.grades,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Report card.
class ReportCardTemplate implements SuiteSheet {
  /// ReportCardTemplate API.
  ReportCardTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.education,
        labels = labels ?? reportCardTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.listing,
          direction: direction,
          theme: theme ?? TemplateThemes.education,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? reportCardTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.grades,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Property listing.
class PropertyListingTemplate implements SuiteSheet {
  /// PropertyListingTemplate API.
  PropertyListingTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.property,
        labels = labels ?? propertyListingTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.listing,
          direction: direction,
          theme: theme ?? TemplateThemes.property,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? propertyListingTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.catalog,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Beneficiary list.
class BeneficiaryListTemplate implements SuiteSheet {
  /// BeneficiaryListTemplate API.
  BeneficiaryListTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.programs,
        labels = labels ?? beneficiaryListTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.listing,
          direction: direction,
          theme: theme ?? TemplateThemes.programs,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? beneficiaryListTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.catalog,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Distribution sheet.
class FieldDistributionTemplate implements SuiteSheet {
  /// FieldDistributionTemplate API.
  FieldDistributionTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.programs,
        labels = labels ?? fieldDistributionTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.listing,
          direction: direction,
          theme: theme ?? TemplateThemes.programs,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? fieldDistributionTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.catalog,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Workshop register.
class WorkshopRegisterTemplate implements SuiteSheet {
  /// WorkshopRegisterTemplate API.
  WorkshopRegisterTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.programs,
        labels = labels ?? workshopRegisterTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.listing,
          direction: direction,
          theme: theme ?? TemplateThemes.programs,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? workshopRegisterTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.checks,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Volunteer hours.
class VolunteerHoursTemplate implements SuiteSheet {
  /// VolunteerHoursTemplate API.
  VolunteerHoursTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.programs,
        labels = labels ?? volunteerHoursTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.listing,
          direction: direction,
          theme: theme ?? TemplateThemes.programs,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? volunteerHoursTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.catalog,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Timesheet.
class TimesheetTemplate implements SuiteSheet {
  /// TimesheetTemplate API.
  TimesheetTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.data,
        labels = labels ?? timesheetTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.listing,
          direction: direction,
          theme: theme ?? TemplateThemes.data,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? timesheetTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.timeline,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Milestone tracker.
class MilestoneTrackerTemplate implements SuiteSheet {
  /// MilestoneTrackerTemplate API.
  MilestoneTrackerTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.data,
        labels = labels ?? milestoneTrackerTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.listing,
          direction: direction,
          theme: theme ?? TemplateThemes.data,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? milestoneTrackerTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.timeline,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Risk register.
class RiskRegisterTemplate implements SuiteSheet {
  /// RiskRegisterTemplate API.
  RiskRegisterTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.data,
        labels = labels ?? riskRegisterTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.listing,
          direction: direction,
          theme: theme ?? TemplateThemes.data,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? riskRegisterTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.catalog,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Issue log.
class IssueLogTemplate implements SuiteSheet {
  /// IssueLogTemplate API.
  IssueLogTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.data,
        labels = labels ?? issueLogTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.listing,
          direction: direction,
          theme: theme ?? TemplateThemes.data,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? issueLogTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.catalog,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Comparison.
class ComparisonTemplate implements SuiteSheet {
  /// ComparisonTemplate API.
  ComparisonTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.data,
        labels = labels ?? comparisonTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.listing,
          direction: direction,
          theme: theme ?? TemplateThemes.data,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? comparisonTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.comparison,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Leaderboard.
class LeaderboardTemplate implements SuiteSheet {
  /// LeaderboardTemplate API.
  LeaderboardTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.data,
        labels = labels ?? leaderboardTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.listing,
          direction: direction,
          theme: theme ?? TemplateThemes.data,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? leaderboardTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.grades,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Exception report.
class ExceptionReportTemplate implements SuiteSheet {
  /// ExceptionReportTemplate API.
  ExceptionReportTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.data,
        labels = labels ?? exceptionReportTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.listing,
          direction: direction,
          theme: theme ?? TemplateThemes.data,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? exceptionReportTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.catalog,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Profit and loss.
class ProfitAndLossTemplate implements SuiteSheet {
  /// ProfitAndLossTemplate API.
  ProfitAndLossTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.finance,
        labels = labels ?? profitAndLossTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.ledger,
          direction: direction,
          theme: theme ?? TemplateThemes.finance,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? profitAndLossTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.statement,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Balance snapshot.
class BalanceSnapshotTemplate implements SuiteSheet {
  /// BalanceSnapshotTemplate API.
  BalanceSnapshotTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.finance,
        labels = labels ?? balanceSnapshotTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.ledger,
          direction: direction,
          theme: theme ?? TemplateThemes.finance,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? balanceSnapshotTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.statement,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Cash flow.
class CashFlowTemplate implements SuiteSheet {
  /// CashFlowTemplate API.
  CashFlowTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.finance,
        labels = labels ?? cashFlowTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.ledger,
          direction: direction,
          theme: theme ?? TemplateThemes.finance,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? cashFlowTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.statement,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Budget versus actual.
class BudgetActualTemplate implements SuiteSheet {
  /// BudgetActualTemplate API.
  BudgetActualTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.finance,
        labels = labels ?? budgetActualTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.ledger,
          direction: direction,
          theme: theme ?? TemplateThemes.finance,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? budgetActualTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.split,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Aged receivables.
class AgedReceivablesTemplate implements SuiteSheet {
  /// AgedReceivablesTemplate API.
  AgedReceivablesTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.finance,
        labels = labels ?? agedReceivablesTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.ledger,
          direction: direction,
          theme: theme ?? TemplateThemes.finance,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? agedReceivablesTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.statement,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Aged payables.
class AgedPayablesTemplate implements SuiteSheet {
  /// AgedPayablesTemplate API.
  AgedPayablesTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.finance,
        labels = labels ?? agedPayablesTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.ledger,
          direction: direction,
          theme: theme ?? TemplateThemes.finance,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? agedPayablesTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.statement,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Journal.
class JournalTemplate implements SuiteSheet {
  /// JournalTemplate API.
  JournalTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.finance,
        labels = labels ?? journalTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.ledger,
          direction: direction,
          theme: theme ?? TemplateThemes.finance,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? journalTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.journal,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Petty cash.
class PettyCashTemplate implements SuiteSheet {
  /// PettyCashTemplate API.
  PettyCashTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.finance,
        labels = labels ?? pettyCashTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.ledger,
          direction: direction,
          theme: theme ?? TemplateThemes.finance,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? pettyCashTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.journal,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Loan schedule.
class LoanScheduleTemplate implements SuiteSheet {
  /// LoanScheduleTemplate API.
  LoanScheduleTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.finance,
        labels = labels ?? loanScheduleTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.ledger,
          direction: direction,
          theme: theme ?? TemplateThemes.finance,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? loanScheduleTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.timeline,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Bank reconciliation.
class BankReconciliationTemplate implements SuiteSheet {
  /// BankReconciliationTemplate API.
  BankReconciliationTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.finance,
        labels = labels ?? bankReconciliationTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.ledger,
          direction: direction,
          theme: theme ?? TemplateThemes.finance,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? bankReconciliationTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.comparison,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Tax summary.
class TaxSummaryTemplate implements SuiteSheet {
  /// TaxSummaryTemplate API.
  TaxSummaryTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.finance,
        labels = labels ?? taxSummaryTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.ledger,
          direction: direction,
          theme: theme ?? TemplateThemes.finance,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? taxSummaryTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.statement,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Payroll summary.
class PayrollSummaryTemplate implements SuiteSheet {
  /// PayrollSummaryTemplate API.
  PayrollSummaryTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.finance,
        labels = labels ?? payrollSummaryTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.ledger,
          direction: direction,
          theme: theme ?? TemplateThemes.finance,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? payrollSummaryTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.split,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Tenant statement.
class TenantStatementTemplate implements SuiteSheet {
  /// TenantStatementTemplate API.
  TenantStatementTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.property,
        labels = labels ?? tenantStatementTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.ledger,
          direction: direction,
          theme: theme ?? TemplateThemes.property,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? tenantStatementTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.statement,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Offer letter.
class OfferLetterTemplate implements SuiteSheet {
  /// OfferLetterTemplate API.
  OfferLetterTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.people,
        labels = labels ?? offerLetterTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.letter,
          direction: direction,
          theme: theme ?? TemplateThemes.people,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? offerLetterTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.letter,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Appointment letter.
class AppointmentLetterTemplate implements SuiteSheet {
  /// AppointmentLetterTemplate API.
  AppointmentLetterTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.people,
        labels = labels ?? appointmentLetterTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.letter,
          direction: direction,
          theme: theme ?? TemplateThemes.people,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? appointmentLetterTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.letter,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Experience letter.
class ExperienceLetterTemplate implements SuiteSheet {
  /// ExperienceLetterTemplate API.
  ExperienceLetterTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.people,
        labels = labels ?? experienceLetterTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.letter,
          direction: direction,
          theme: theme ?? TemplateThemes.people,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? experienceLetterTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.identity,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Warning notice.
class WarningNoticeTemplate implements SuiteSheet {
  /// WarningNoticeTemplate API.
  WarningNoticeTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.people,
        labels = labels ?? warningNoticeTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.letter,
          direction: direction,
          theme: theme ?? TemplateThemes.people,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? warningNoticeTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.notice,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Recommendation.
class RecommendationLetterTemplate implements SuiteSheet {
  /// RecommendationLetterTemplate API.
  RecommendationLetterTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.people,
        labels = labels ?? recommendationLetterTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.letter,
          direction: direction,
          theme: theme ?? TemplateThemes.people,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? recommendationLetterTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.letter,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Leave request.
class LeaveRequestTemplate implements SuiteSheet {
  /// LeaveRequestTemplate API.
  LeaveRequestTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.people,
        labels = labels ?? leaveRequestTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.letter,
          direction: direction,
          theme: theme ?? TemplateThemes.people,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? leaveRequestTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.letter,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Welcome note.
class WelcomeNoteTemplate implements SuiteSheet {
  /// WelcomeNoteTemplate API.
  WelcomeNoteTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.people,
        labels = labels ?? welcomeNoteTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.letter,
          direction: direction,
          theme: theme ?? TemplateThemes.people,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? welcomeNoteTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.letter,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Relieving letter.
class RelievingLetterTemplate implements SuiteSheet {
  /// RelievingLetterTemplate API.
  RelievingLetterTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.people,
        labels = labels ?? relievingLetterTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.letter,
          direction: direction,
          theme: theme ?? TemplateThemes.people,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? relievingLetterTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.letter,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Reference letter.
class ReferenceLetterTemplate implements SuiteSheet {
  /// ReferenceLetterTemplate API.
  ReferenceLetterTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.people,
        labels = labels ?? referenceLetterTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.letter,
          direction: direction,
          theme: theme ?? TemplateThemes.people,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? referenceLetterTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.identity,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Admission letter.
class AdmissionLetterTemplate implements SuiteSheet {
  /// AdmissionLetterTemplate API.
  AdmissionLetterTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.education,
        labels = labels ?? admissionLetterTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.letter,
          direction: direction,
          theme: theme ?? TemplateThemes.education,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? admissionLetterTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.letter,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Announcement.
class AnnouncementTemplate implements SuiteSheet {
  /// AnnouncementTemplate API.
  AnnouncementTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.narrative,
        labels = labels ?? announcementTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.letter,
          direction: direction,
          theme: theme ?? TemplateThemes.narrative,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? announcementTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.notice,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Meeting notice.
class MeetingNoticeTemplate implements SuiteSheet {
  /// MeetingNoticeTemplate API.
  MeetingNoticeTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.narrative,
        labels = labels ?? meetingNoticeTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.letter,
          direction: direction,
          theme: theme ?? TemplateThemes.narrative,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? meetingNoticeTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.notice,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Decision note.
class DecisionNoteTemplate implements SuiteSheet {
  /// DecisionNoteTemplate API.
  DecisionNoteTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.narrative,
        labels = labels ?? decisionNoteTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.letter,
          direction: direction,
          theme: theme ?? TemplateThemes.narrative,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? decisionNoteTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.notice,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Internship certificate.
class InternshipCertificateTemplate implements SuiteSheet {
  /// InternshipCertificateTemplate API.
  InternshipCertificateTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.people,
        labels = labels ?? internshipCertificateTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.award,
          direction: direction,
          theme: theme ?? TemplateThemes.people,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? internshipCertificateTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: true,
          skin: SheetSkin.certificate,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Press release.
class PressReleaseTemplate implements SuiteSheet {
  /// PressReleaseTemplate API.
  PressReleaseTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.narrative,
        labels = labels ?? pressReleaseTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.brief,
          direction: direction,
          theme: theme ?? TemplateThemes.narrative,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? pressReleaseTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.masthead,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Project status.
class ProjectStatusTemplate implements SuiteSheet {
  /// ProjectStatusTemplate API.
  ProjectStatusTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.narrative,
        labels = labels ?? projectStatusTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.brief,
          direction: direction,
          theme: theme ?? TemplateThemes.narrative,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? projectStatusTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.masthead,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Policy note.
class PolicyNoteTemplate implements SuiteSheet {
  /// PolicyNoteTemplate API.
  PolicyNoteTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.narrative,
        labels = labels ?? policyNoteTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.brief,
          direction: direction,
          theme: theme ?? TemplateThemes.narrative,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? policyNoteTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.notice,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Executive summary.
class ExecutiveSummaryTemplate implements SuiteSheet {
  /// ExecutiveSummaryTemplate API.
  ExecutiveSummaryTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.narrative,
        labels = labels ?? executiveSummaryTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.brief,
          direction: direction,
          theme: theme ?? TemplateThemes.narrative,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? executiveSummaryTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.masthead,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// After-action review.
class AfterActionTemplate implements SuiteSheet {
  /// AfterActionTemplate API.
  AfterActionTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.narrative,
        labels = labels ?? afterActionTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.brief,
          direction: direction,
          theme: theme ?? TemplateThemes.narrative,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? afterActionTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.masthead,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Newsletter.
class NewsletterTemplate implements SuiteSheet {
  /// NewsletterTemplate API.
  NewsletterTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.narrative,
        labels = labels ?? newsletterTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.brief,
          direction: direction,
          theme: theme ?? TemplateThemes.narrative,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? newsletterTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.masthead,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Proposal.
class ProposalTemplate implements SuiteSheet {
  /// ProposalTemplate API.
  ProposalTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.narrative,
        labels = labels ?? proposalTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.brief,
          direction: direction,
          theme: theme ?? TemplateThemes.narrative,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? proposalTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.masthead,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Safety briefing.
class SafetyBriefingTemplate implements SuiteSheet {
  /// SafetyBriefingTemplate API.
  SafetyBriefingTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.operations,
        labels = labels ?? safetyBriefingTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.brief,
          direction: direction,
          theme: theme ?? TemplateThemes.operations,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? safetyBriefingTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.notice,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Incident report.
class IncidentReportTemplate implements SuiteSheet {
  /// IncidentReportTemplate API.
  IncidentReportTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.operations,
        labels = labels ?? incidentReportTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.brief,
          direction: direction,
          theme: theme ?? TemplateThemes.operations,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? incidentReportTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.notice,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Handover.
class HandoverNoteTemplate implements SuiteSheet {
  /// HandoverNoteTemplate API.
  HandoverNoteTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.operations,
        labels = labels ?? handoverNoteTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.brief,
          direction: direction,
          theme: theme ?? TemplateThemes.operations,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? handoverNoteTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.route,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Change request.
class ChangeRequestTemplate implements SuiteSheet {
  /// ChangeRequestTemplate API.
  ChangeRequestTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.operations,
        labels = labels ?? changeRequestTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.brief,
          direction: direction,
          theme: theme ?? TemplateThemes.operations,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? changeRequestTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.notice,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Syllabus.
class SyllabusTemplate implements SuiteSheet {
  /// SyllabusTemplate API.
  SyllabusTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.education,
        labels = labels ?? syllabusTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.brief,
          direction: direction,
          theme: theme ?? TemplateThemes.education,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? syllabusTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.masthead,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Assignment brief.
class AssignmentBriefTemplate implements SuiteSheet {
  /// AssignmentBriefTemplate API.
  AssignmentBriefTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.education,
        labels = labels ?? assignmentBriefTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.brief,
          direction: direction,
          theme: theme ?? TemplateThemes.education,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? assignmentBriefTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.notice,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Progress report.
class ProgressReportTemplate implements SuiteSheet {
  /// ProgressReportTemplate API.
  ProgressReportTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.education,
        labels = labels ?? progressReportTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.brief,
          direction: direction,
          theme: theme ?? TemplateThemes.education,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? progressReportTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.letter,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Lease summary.
class LeaseSummaryTemplate implements SuiteSheet {
  /// LeaseSummaryTemplate API.
  LeaseSummaryTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.property,
        labels = labels ?? leaseSummaryTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.brief,
          direction: direction,
          theme: theme ?? TemplateThemes.property,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? leaseSummaryTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.letter,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Grant report.
class GrantReportTemplate implements SuiteSheet {
  /// GrantReportTemplate API.
  GrantReportTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.programs,
        labels = labels ?? grantReportTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.brief,
          direction: direction,
          theme: theme ?? TemplateThemes.programs,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? grantReportTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.masthead,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Program brief.
class ProgramBriefTemplate implements SuiteSheet {
  /// ProgramBriefTemplate API.
  ProgramBriefTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.programs,
        labels = labels ?? programBriefTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.brief,
          direction: direction,
          theme: theme ?? TemplateThemes.programs,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? programBriefTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.masthead,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Work permit.
class WorkPermitTemplate implements SuiteSheet {
  /// WorkPermitTemplate API.
  WorkPermitTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.operations,
        labels = labels ?? workPermitTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.check,
          direction: direction,
          theme: theme ?? TemplateThemes.operations,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? workPermitTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.checks,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Audit findings.
class AuditFindingsTemplate implements SuiteSheet {
  /// AuditFindingsTemplate API.
  AuditFindingsTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.operations,
        labels = labels ?? auditFindingsTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.check,
          direction: direction,
          theme: theme ?? TemplateThemes.operations,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? auditFindingsTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.checks,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Move-in checklist.
class MoveInChecklistTemplate implements SuiteSheet {
  /// MoveInChecklistTemplate API.
  MoveInChecklistTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.property,
        labels = labels ?? moveInChecklistTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.check,
          direction: direction,
          theme: theme ?? TemplateThemes.property,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? moveInChecklistTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.checks,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Maintenance request.
class MaintenanceRequestTemplate implements SuiteSheet {
  /// MaintenanceRequestTemplate API.
  MaintenanceRequestTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.property,
        labels = labels ?? maintenanceRequestTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.check,
          direction: direction,
          theme: theme ?? TemplateThemes.property,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? maintenanceRequestTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.checks,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Scorecard.
class ScorecardTemplate implements SuiteSheet {
  /// ScorecardTemplate API.
  ScorecardTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.data,
        labels = labels ?? scorecardTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.score,
          direction: direction,
          theme: theme ?? TemplateThemes.data,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? scorecardTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.tiles,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Survey results.
class SurveyResultsTemplate implements SuiteSheet {
  /// SurveyResultsTemplate API.
  SurveyResultsTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.data,
        labels = labels ?? surveyResultsTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.score,
          direction: direction,
          theme: theme ?? TemplateThemes.data,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? surveyResultsTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.tiles,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Capacity report.
class CapacityReportTemplate implements SuiteSheet {
  /// CapacityReportTemplate API.
  CapacityReportTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.data,
        labels = labels ?? capacityReportTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.score,
          direction: direction,
          theme: theme ?? TemplateThemes.data,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? capacityReportTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.tiles,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Impact sheet.
class ImpactSheetTemplate implements SuiteSheet {
  /// ImpactSheetTemplate API.
  ImpactSheetTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.programs,
        labels = labels ?? impactSheetTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.score,
          direction: direction,
          theme: theme ?? TemplateThemes.programs,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? impactSheetTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.tiles,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Daily site report.
class DailySiteReportTemplate implements SuiteSheet {
  /// DailySiteReportTemplate API.
  DailySiteReportTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.operations,
        labels = labels ?? dailySiteReportTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.score,
          direction: direction,
          theme: theme ?? TemplateThemes.operations,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? dailySiteReportTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.tiles,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Employee profile.
class EmployeeProfileTemplate implements SuiteSheet {
  /// EmployeeProfileTemplate API.
  EmployeeProfileTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.people,
        labels = labels ?? employeeProfileTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.score,
          direction: direction,
          theme: theme ?? TemplateThemes.people,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? employeeProfileTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.identity,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Maintenance log.
class MaintenanceLogTemplate implements SuiteSheet {
  /// MaintenanceLogTemplate API.
  MaintenanceLogTemplate({
    this.direction = TextDirection.ltr,
    TemplateTheme? theme,
    this.font,
    this.fontBold,
    required this.from,
    this.to,
    SheetLabels? labels,
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  })  : theme = theme ?? TemplateThemes.operations,
        labels = labels ?? maintenanceLogTemplateLabels,
        _sheet = SheetTemplate(
          kind: SheetKind.score,
          direction: direction,
          theme: theme ?? TemplateThemes.operations,
          font: font,
          fontBold: fontBold,
          owner: from,
          other: to,
          labels: labels ?? maintenanceLogTemplateLabels,
          number: number,
          date: date,
          extra: extra,
          subject: subject,
          recipient: recipient,
          rows: rows,
          paragraphs: paragraphs,
          sections: sections,
          metrics: metrics,
          chart: chart,
          chartTitle: chartTitle,
          totals: totals,
          notes: notes,
          footer: footer,
          signs: signs,
          landscape: false,
          skin: SheetSkin.tiles,
        );

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty? to;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// recipient API.
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  final SheetTemplate _sheet;

  @override
  Uint8List save() => _sheet.save();
}

/// Builds a suite template by catalog id. Labels default to English.
abstract final class TemplateSuite {
  /// ids API.
  static const Set<String> ids = <String>{
    'commerce.purchase-order', 'commerce.sales-order', 'commerce.credit-note', 'commerce.debit-note', 'commerce.proforma', 'commerce.service-estimate', 'commerce.commission', 'logistics.bill', 'logistics.freight-quote', 'education.fee-receipt', 'property.rent-receipt', 'programs.donation', 'finance.payment-voucher', 'finance.receipt-voucher', 'commerce.packing-list', 'commerce.price-list', 'commerce.goods-received', 'commerce.return', 'commerce.consignment', 'operations.goods-issue', 'operations.inventory', 'operations.assets', 'operations.visitors', 'operations.roster', 'operations.ticket', 'logistics.pick-list', 'logistics.manifest', 'logistics.waybill', 'logistics.transfer', 'logistics.load-sheet', 'logistics.notice', 'people.attendance', 'education.register', 'education.transcript', 'education.report-card', 'property.listing', 'programs.beneficiaries', 'programs.distribution', 'programs.workshop', 'programs.volunteers', 'data.timesheet', 'data.milestones', 'data.risks', 'data.issues', 'data.comparison', 'data.leaderboard', 'data.exceptions', 'finance.profit-loss', 'finance.balance', 'finance.cash-flow', 'finance.budget-actual', 'finance.aged-receivables', 'finance.aged-payables', 'finance.journal', 'finance.petty-cash', 'finance.loan-schedule', 'finance.reconciliation', 'finance.tax-summary', 'finance.payroll-summary', 'property.tenant-statement', 'people.offer', 'people.appointment', 'people.experience', 'people.warning', 'people.recommendation', 'people.leave', 'people.welcome', 'people.relieving', 'people.reference', 'education.admission', 'narrative.announcement', 'narrative.meeting-notice', 'narrative.decision', 'people.internship', 'narrative.press', 'narrative.project-status', 'narrative.policy', 'narrative.executive', 'narrative.after-action', 'narrative.newsletter', 'narrative.proposal', 'operations.safety', 'operations.incident', 'operations.handover', 'operations.change', 'education.syllabus', 'education.assignment', 'education.progress', 'property.lease', 'programs.grant', 'programs.brief', 'operations.permit', 'operations.audit', 'property.move-in', 'property.maintenance', 'data.scorecard', 'data.survey', 'data.capacity', 'programs.impact', 'operations.daily-site', 'people.profile', 'operations.maintenance',
  };

  static final Map<String, SuiteCtor> _ctors = <String, SuiteCtor>{
  'commerce.purchase-order': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      PurchaseOrderTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'commerce.sales-order': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      SalesOrderTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'commerce.credit-note': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      CreditNoteTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'commerce.debit-note': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      DebitNoteTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'commerce.proforma': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      ProformaTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'commerce.service-estimate': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      ServiceEstimateTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'commerce.commission': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      CommissionNoteTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'logistics.bill': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      BillOfLadingTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'logistics.freight-quote': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      FreightQuoteTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'education.fee-receipt': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      FeeReceiptTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'property.rent-receipt': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      RentReceiptTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'programs.donation': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      DonationReceiptTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'finance.payment-voucher': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      PaymentVoucherTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'finance.receipt-voucher': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      ReceiptVoucherTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'commerce.packing-list': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      PackingListTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'commerce.price-list': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      PriceListTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'commerce.goods-received': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      GoodsReceivedTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'commerce.return': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      ReturnAuthorizationTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'commerce.consignment': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      ConsignmentNoteTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'operations.goods-issue': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      GoodsIssueTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'operations.inventory': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      InventoryCountTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'operations.assets': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      AssetRegisterTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'operations.visitors': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      VisitorLogTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'operations.roster': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      ShiftRosterTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'operations.ticket': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      ServiceTicketTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'logistics.pick-list': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      PickListTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'logistics.manifest': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      DeliveryManifestTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'logistics.waybill': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      WaybillTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'logistics.transfer': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      WarehouseTransferTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'logistics.load-sheet': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      LoadSheetTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'logistics.notice': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      ShippingNoticeTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'people.attendance': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      AttendanceSheetTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'education.register': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      ClassRegisterTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'education.transcript': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      TranscriptTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'education.report-card': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      ReportCardTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'property.listing': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      PropertyListingTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'programs.beneficiaries': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      BeneficiaryListTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'programs.distribution': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      FieldDistributionTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'programs.workshop': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      WorkshopRegisterTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'programs.volunteers': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      VolunteerHoursTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'data.timesheet': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      TimesheetTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'data.milestones': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      MilestoneTrackerTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'data.risks': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      RiskRegisterTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'data.issues': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      IssueLogTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'data.comparison': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      ComparisonTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'data.leaderboard': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      LeaderboardTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'data.exceptions': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      ExceptionReportTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'finance.profit-loss': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      ProfitAndLossTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'finance.balance': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      BalanceSnapshotTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'finance.cash-flow': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      CashFlowTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'finance.budget-actual': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      BudgetActualTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'finance.aged-receivables': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      AgedReceivablesTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'finance.aged-payables': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      AgedPayablesTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'finance.journal': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      JournalTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'finance.petty-cash': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      PettyCashTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'finance.loan-schedule': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      LoanScheduleTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'finance.reconciliation': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      BankReconciliationTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'finance.tax-summary': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      TaxSummaryTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'finance.payroll-summary': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      PayrollSummaryTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'property.tenant-statement': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      TenantStatementTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'people.offer': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      OfferLetterTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'people.appointment': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      AppointmentLetterTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'people.experience': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      ExperienceLetterTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'people.warning': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      WarningNoticeTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'people.recommendation': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      RecommendationLetterTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'people.leave': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      LeaveRequestTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'people.welcome': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      WelcomeNoteTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'people.relieving': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      RelievingLetterTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'people.reference': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      ReferenceLetterTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'education.admission': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      AdmissionLetterTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'narrative.announcement': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      AnnouncementTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'narrative.meeting-notice': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      MeetingNoticeTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'narrative.decision': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      DecisionNoteTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'people.internship': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      InternshipCertificateTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'narrative.press': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      PressReleaseTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'narrative.project-status': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      ProjectStatusTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'narrative.policy': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      PolicyNoteTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'narrative.executive': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      ExecutiveSummaryTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'narrative.after-action': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      AfterActionTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'narrative.newsletter': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      NewsletterTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'narrative.proposal': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      ProposalTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'operations.safety': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      SafetyBriefingTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'operations.incident': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      IncidentReportTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'operations.handover': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      HandoverNoteTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'operations.change': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      ChangeRequestTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'education.syllabus': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      SyllabusTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'education.assignment': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      AssignmentBriefTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'education.progress': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      ProgressReportTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'property.lease': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      LeaseSummaryTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'programs.grant': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      GrantReportTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'programs.brief': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      ProgramBriefTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'operations.permit': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      WorkPermitTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'operations.audit': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      AuditFindingsTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'property.move-in': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      MoveInChecklistTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'property.maintenance': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      MaintenanceRequestTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'data.scorecard': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      ScorecardTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'data.survey': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      SurveyResultsTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'data.capacity': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      CapacityReportTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'programs.impact': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      ImpactSheetTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'operations.daily-site': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      DailySiteReportTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'people.profile': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      EmployeeProfileTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      ),
  'operations.maintenance': ({
    TextDirection direction = TextDirection.ltr,
    TemplateTheme? theme,
    SfntFont? font,
    SfntFont? fontBold,
    required TemplateParty from,
    TemplateParty? to,
    SheetLabels? labels,
    String number = '',
    String date = '',
    String extra = '',
    String subject = '',
    String recipient = '',
    List<SheetRow> rows = const <SheetRow>[],
    List<String> paragraphs = const <String>[],
    List<TemplateSection> sections = const <TemplateSection>[],
    List<(String, String)> metrics = const <(String, String)>[],
    List<ChartPoint>? chart,
    String chartTitle = '',
    MoneyTotals? totals,
    String? notes,
    String footer = '',
    List<SignSlot> signs = const <SignSlot>[],
  }) =>
      MaintenanceLogTemplate(
        direction: direction,
        theme: theme,
        font: font,
        fontBold: fontBold,
        from: from,
        to: to,
        labels: labels,
        number: number,
        date: date,
        extra: extra,
        subject: subject,
        recipient: recipient,
        rows: rows,
        paragraphs: paragraphs,
        sections: sections,
        metrics: metrics,
        chart: chart,
        chartTitle: chartTitle,
        totals: totals,
        notes: notes,
        footer: footer,
        signs: signs,
      )
  };

  /// demo API. One page. [arabic] swaps labels, direction, and sample text.
  static Uint8List demo(
    String id, {
    required bool arabic,
    SfntFont? font,
    SfntFont? fontBold,
  }) {
    final SuiteCtor? ctor = _ctors[id];
    if (ctor == null) {
      throw ArgumentError('Unknown suite template: $id');
    }
    return switch (id) {
    'commerce.purchase-order' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'الرصيف الشمالي' : 'North Dock',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'توريدات الميناء' : 'Harbour Supply'),
        labels: arabic
            ? SheetLabels(
              document: 'أمر شراء',
              from: 'المشتري',
              to: 'المورّد',
              number: 'الأمر',
              date: 'التاريخ',
              extra: 'مطلوب في',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'الكمية',
                'السعر',
                'المبلغ',
              ],
            )
            : SheetLabels(
              document: 'Purchase order',
              from: 'Buyer',
              to: 'Supplier',
              number: 'PO',
              date: 'Date',
              extra: 'Needed by',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Qty',
                'Unit',
                'Amount',
              ],
            ),
        number: 'PO-14',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? '28 أيلول 2026' : '28 Sep 2026',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['حقيبة ميدانية', '12', '48', '576']),
            SheetRow(<String>['صندوق تبريد', '4', '90', '360']),
          ] : const <SheetRow>[
            SheetRow(<String>['Field kit', '12', '48', '576']),
            SheetRow(<String>['Cold box', '4', '90', '360']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: const MoneyTotals(subtotal: '936', tax: '140', total: '1,076'),
        notes: arabic ? 'أرفق قائمة التعبئة مع الصناديق.' : 'Send the packing list with the crates.',
        footer: arabic ? 'الرصيف الشمالي' : 'North Dock',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'commerce.sales-order' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'توريدات الميناء' : 'Harbour Supply',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'عيادة النهر' : 'River Clinic'),
        labels: arabic
            ? SheetLabels(
              document: 'أمر بيع',
              from: 'البائع',
              to: 'المشتري',
              number: 'الطلب',
              date: 'التاريخ',
              extra: 'الشحن قبل',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'الكمية',
                'المبلغ',
              ],
            )
            : SheetLabels(
              document: 'Sales order',
              from: 'Seller',
              to: 'Buyer',
              number: 'Order',
              date: 'Date',
              extra: 'Ship by',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Qty',
                'Amount',
              ],
            ),
        number: 'SO-88',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? '20 أيلول 2026' : '20 Sep 2026',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['صابون عيادة', '40', '200']),
            SheetRow(<String>['لفّة شاش', '20', '160']),
          ] : const <SheetRow>[
            SheetRow(<String>['Clinic soap', '40', '200']),
            SheetRow(<String>['Gauze roll', '20', '160']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: const MoneyTotals(subtotal: '936', tax: '140', total: '1,076'),
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'توريدات الميناء' : 'Harbour Supply',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'commerce.credit-note' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'الرصيف الشمالي' : 'North Dock',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'عيادة النهر' : 'River Clinic'),
        labels: arabic
            ? SheetLabels(
              document: 'إشعار دائن',
              from: 'المُصدِر',
              to: 'الحساب',
              number: 'الإشعار',
              date: 'التاريخ',
              extra: 'الفاتورة',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'السبب',
                'الكمية',
                'الدائن',
              ],
            )
            : SheetLabels(
              document: 'Credit note',
              from: 'Issuer',
              to: 'Account',
              number: 'Credit',
              date: 'Date',
              extra: 'Invoice',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Reason',
                'Qty',
                'Credit',
              ],
            ),
        number: 'CN-3',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'INV-14' : 'INV-14',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['نقص في الشحنة', '2', '96']),
            SheetRow(<String>['غطاء تالف', '1', '40']),
          ] : const <SheetRow>[
            SheetRow(<String>['Short shipment', '2', '96']),
            SheetRow(<String>['Damaged lid', '1', '40']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: const MoneyTotals(subtotal: '136', tax: '0', total: '136'),
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'الرصيف الشمالي' : 'North Dock',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'commerce.debit-note' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'الرصيف الشمالي' : 'North Dock',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'عيادة النهر' : 'River Clinic'),
        labels: arabic
            ? SheetLabels(
              document: 'إشعار مدين',
              from: 'المُصدِر',
              to: 'الحساب',
              number: 'الإشعار',
              date: 'التاريخ',
              extra: 'الفاتورة',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'السبب',
                'الكمية',
                'القيد',
              ],
            )
            : SheetLabels(
              document: 'Debit note',
              from: 'Issuer',
              to: 'Account',
              number: 'Debit',
              date: 'Date',
              extra: 'Invoice',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Reason',
                'Qty',
                'Charge',
              ],
            ),
        number: 'DN-2',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'INV-14' : 'INV-14',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['مناولة مستعجلة', '1', '75']),
            SheetRow(<String>['بوابة ليلية', '1', '40']),
          ] : const <SheetRow>[
            SheetRow(<String>['Rush handling', '1', '75']),
            SheetRow(<String>['Night gate', '1', '40']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: const MoneyTotals(subtotal: '115', tax: '0', total: '115'),
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'الرصيف الشمالي' : 'North Dock',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'commerce.proforma' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'الرصيف الشمالي' : 'North Dock',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'عيادة النهر' : 'River Clinic'),
        labels: arabic
            ? SheetLabels(
              document: 'فاتورة مبدئية',
              from: 'البائع',
              to: 'المشتري',
              number: 'المبدئية',
              date: 'التاريخ',
              extra: 'صالحة حتى',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'الكمية',
                'المبلغ',
              ],
            )
            : SheetLabels(
              document: 'Proforma invoice',
              from: 'Seller',
              to: 'Buyer',
              number: 'Proforma',
              date: 'Date',
              extra: 'Valid until',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Qty',
                'Amount',
              ],
            ),
        number: 'PF-9',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? '30 أيلول 2026' : '30 Sep 2026',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['هيكل خيمة', '6', '720']),
            SheetRow(<String>['عازل أرض', '6', '180']),
          ] : const <SheetRow>[
            SheetRow(<String>['Tent frame', '6', '720']),
            SheetRow(<String>['Ground sheet', '6', '180']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: const MoneyTotals(subtotal: '900', tax: '0', total: '900'),
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'الرصيف الشمالي' : 'North Dock',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'commerce.service-estimate' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'ورشة الرصيف' : 'Dock Workshop',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'عيادة النهر' : 'River Clinic'),
        labels: arabic
            ? SheetLabels(
              document: 'تقدير خدمة',
              from: 'الورشة',
              to: 'العميل',
              number: 'التقدير',
              date: 'التاريخ',
              extra: 'صالح حتى',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'المهمة',
                'الساعات',
                'المبلغ',
              ],
            )
            : SheetLabels(
              document: 'Service estimate',
              from: 'Workshop',
              to: 'Client',
              number: 'Estimate',
              date: 'Date',
              extra: 'Valid until',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Task',
                'Hours',
                'Amount',
              ],
            ),
        number: 'ES-21',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? '21 أيلول 2026' : '21 Sep 2026',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['محرّك البوابة', '3', '240']),
            SheetRow(<String>['حسّاس', '1', '90']),
          ] : const <SheetRow>[
            SheetRow(<String>['Gate motor', '3', '240']),
            SheetRow(<String>['Sensor', '1', '90']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: const MoneyTotals(subtotal: '330', tax: '50', total: '380'),
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'ورشة الرصيف' : 'Dock Workshop',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'commerce.commission' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'الرصيف الشمالي' : 'North Dock',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'لينا حداد' : 'Lina Haddad'),
        labels: arabic
            ? SheetLabels(
              document: 'كشف عمولة',
              from: 'الجهة',
              to: 'الوكيل',
              number: 'الكشف',
              date: 'التاريخ',
              extra: 'الفترة',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'الصفقة',
                'الأساس',
                'النسبة',
                'العمولة',
              ],
            )
            : SheetLabels(
              document: 'Commission note',
              from: 'House',
              to: 'Agent',
              number: 'Note',
              date: 'Date',
              extra: 'Period',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Deal',
                'Base',
                'Rate',
                'Commission',
              ],
            ),
        number: 'CM-7',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'أيلول' : 'September',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['حقائب العيادة', '1,076', '5%', '54']),
            SheetRow(<String>['إصلاح البوابة', '380', '8%', '30']),
          ] : const <SheetRow>[
            SheetRow(<String>['Clinic kits', '1,076', '5%', '54']),
            SheetRow(<String>['Gate repair', '380', '8%', '30']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: const MoneyTotals(subtotal: '84', tax: '0', total: '84'),
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'الرصيف الشمالي' : 'North Dock',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'logistics.bill' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'الرصيف الشمالي' : 'North Dock',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'عيادة النهر' : 'River Clinic'),
        labels: arabic
            ? SheetLabels(
              document: 'بوليصة شحن',
              from: 'الشاحن',
              to: 'المرسل إليه',
              number: 'البوليصة',
              date: 'التاريخ',
              extra: 'السفينة',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'العلامات',
                'الكمية',
                'الوزن',
                'البضاعة',
              ],
            )
            : SheetLabels(
              document: 'Bill of lading',
              from: 'Shipper',
              to: 'Consignee',
              number: 'B/L',
              date: 'Date',
              extra: 'Vessel',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Marks',
                'Qty',
                'Weight',
                'Goods',
              ],
            ),
        number: 'BL-44',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'فجر الميناء' : 'Harbour Dawn',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['ND-12', '12', '180 كغ', 'حقائب ميدانية']),
            SheetRow(<String>['ND-4', '4', '60 كغ', 'صناديق تبريد']),
          ] : const <SheetRow>[
            SheetRow(<String>['ND-12', '12', '180 kg', 'Field kits']),
            SheetRow(<String>['ND-4', '4', '60 kg', 'Cold boxes']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'الرصيف الشمالي' : 'North Dock',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'logistics.freight-quote' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'شحن الساحل' : 'Coast Freight',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'الرصيف الشمالي' : 'North Dock'),
        labels: arabic
            ? SheetLabels(
              document: 'عرض شحن',
              from: 'الناقل',
              to: 'الشاحن',
              number: 'العرض',
              date: 'التاريخ',
              extra: 'المسار',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'المرحلة',
                'الوزن',
                'المبلغ',
              ],
            )
            : SheetLabels(
              document: 'Freight quote',
              from: 'Carrier',
              to: 'Shipper',
              number: 'Quote',
              date: 'Date',
              extra: 'Lane',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Leg',
                'Weight',
                'Amount',
              ],
            ),
        number: 'FQ-5',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'من الرصيف إلى العيادة' : 'Dock to clinic',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['بري', '240 كغ', '180']),
            SheetRow(<String>['مناولة', '1', '40']),
          ] : const <SheetRow>[
            SheetRow(<String>['Road', '240 kg', '180']),
            SheetRow(<String>['Handling', '1', '40']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: const MoneyTotals(subtotal: '220', tax: '0', total: '220'),
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'شحن الساحل' : 'Coast Freight',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'education.fee-receipt' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'مدرسة النهر' : 'River School',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'عائلة حداد' : 'Haddad family'),
        labels: arabic
            ? SheetLabels(
              document: 'إيصال رسوم',
              from: 'المدرسة',
              to: 'الدافع',
              number: 'الإيصال',
              date: 'التاريخ',
              extra: 'الفصل',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'الرسم',
                'البيان',
                'المبلغ',
              ],
            )
            : SheetLabels(
              document: 'Fee receipt',
              from: 'School',
              to: 'Payer',
              number: 'Receipt',
              date: 'Date',
              extra: 'Term',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Fee',
                'Detail',
                'Amount',
              ],
            ),
        number: 'FR-19',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'خريف 2026' : 'Autumn 2026',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['قسط', 'الخريف', '800']),
            SheetRow(<String>['مختبر', 'علوم', '60']),
          ] : const <SheetRow>[
            SheetRow(<String>['Tuition', 'Autumn', '800']),
            SheetRow(<String>['Lab', 'Science', '60']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: const MoneyTotals(subtotal: '860', tax: '0', total: '860'),
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'مدرسة النهر' : 'River School',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'property.rent-receipt' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'إسكان الرصيف' : 'Dock Housing',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'سامي ناصر' : 'Sami Nasser'),
        labels: arabic
            ? SheetLabels(
              document: 'إيصال إيجار',
              from: 'المالك',
              to: 'المستأجر',
              number: 'الإيصال',
              date: 'التاريخ',
              extra: 'الشهر',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'الفترة',
                'المبلغ',
              ],
            )
            : SheetLabels(
              document: 'Rent receipt',
              from: 'Landlord',
              to: 'Tenant',
              number: 'Receipt',
              date: 'Date',
              extra: 'Month',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Charge',
                'Period',
                'Amount',
              ],
            ),
        number: 'RR-9',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'أيلول 2026' : 'September 2026',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['إيجار', 'أيلول', '650']),
            SheetRow(<String>['ماء', 'أيلول', '18']),
          ] : const <SheetRow>[
            SheetRow(<String>['Rent', 'September', '650']),
            SheetRow(<String>['Water', 'September', '18']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: const MoneyTotals(subtotal: '668', tax: '0', total: '668'),
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'إسكان الرصيف' : 'Dock Housing',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'programs.donation' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'صندوق النهر' : 'River Fund',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'الرصيف الشمالي' : 'North Dock'),
        labels: arabic
            ? SheetLabels(
              document: 'إيصال تبرع',
              from: 'الصندوق',
              to: 'المتبرع',
              number: 'الإيصال',
              date: 'التاريخ',
              extra: 'الصندوق',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'الهدية',
                'البيان',
                'المبلغ',
              ],
            )
            : SheetLabels(
              document: 'Donation receipt',
              from: 'Fund',
              to: 'Donor',
              number: 'Receipt',
              date: 'Date',
              extra: 'Fund',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Gift',
                'Detail',
                'Amount',
              ],
            ),
        number: 'DR-4',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'حقائب العيادة' : 'Clinic kits',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['نقد', 'حقائب', '500']),
            SheetRow(<String>['عين', 'بطانيات', '200']),
          ] : const <SheetRow>[
            SheetRow(<String>['Cash', 'Kits', '500']),
            SheetRow(<String>['Goods', 'Blankets', '200']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: const MoneyTotals(subtotal: '700', tax: '0', total: '700'),
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'صندوق النهر' : 'River Fund',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'finance.payment-voucher' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'الرصيف الشمالي' : 'North Dock',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'عيادة النهر' : 'River Clinic'),
        labels: arabic
            ? SheetLabels(
              document: 'سند صرف',
              from: 'الصارف',
              to: 'المستفيد',
              number: 'السند',
              date: 'التاريخ',
              extra: 'الطريقة',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'الغرض',
                'المرجع',
                'المبلغ',
              ],
            )
            : SheetLabels(
              document: 'Payment voucher',
              from: 'Payer',
              to: 'Payee',
              number: 'Voucher',
              date: 'Date',
              extra: 'Method',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Purpose',
                'Ref',
                'Amount',
              ],
            ),
        number: 'PV-31',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'تحويل' : 'Transfer',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['إصلاح البوابة', 'WO-6', '380']),
            SheetRow(<String>['وردية ليل', 'RS-2', '90']),
          ] : const <SheetRow>[
            SheetRow(<String>['Gate repair', 'WO-6', '380']),
            SheetRow(<String>['Night shift', 'RS-2', '90']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: const MoneyTotals(subtotal: '470', tax: '0', total: '470'),
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'الرصيف الشمالي' : 'North Dock',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'finance.receipt-voucher' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'الرصيف الشمالي' : 'North Dock',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'عيادة النهر' : 'River Clinic'),
        labels: arabic
            ? SheetLabels(
              document: 'سند قبض',
              from: 'القابض',
              to: 'الدافع',
              number: 'السند',
              date: 'التاريخ',
              extra: 'الطريقة',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'الغرض',
                'المرجع',
                'المبلغ',
              ],
            )
            : SheetLabels(
              document: 'Receipt voucher',
              from: 'Receiver',
              to: 'Payer',
              number: 'Voucher',
              date: 'Date',
              extra: 'Method',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Purpose',
                'Ref',
                'Amount',
              ],
            ),
        number: 'RV-12',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'نقد' : 'Cash',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['عربون الحقائب', 'SO-88', '200']),
            SheetRow(<String>['إيجار', 'RR-9', '668']),
          ] : const <SheetRow>[
            SheetRow(<String>['Kit deposit', 'SO-88', '200']),
            SheetRow(<String>['Rent', 'RR-9', '668']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: const MoneyTotals(subtotal: '868', tax: '0', total: '868'),
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'الرصيف الشمالي' : 'North Dock',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'commerce.packing-list' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'الرصيف الشمالي' : 'North Dock',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'عيادة النهر' : 'River Clinic'),
        labels: arabic
            ? SheetLabels(
              document: 'قائمة تعبئة',
              from: 'المعبّئ',
              to: 'المستلم',
              number: 'القائمة',
              date: 'التاريخ',
              extra: 'الصناديق',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'المطلوب',
                'المعبأ',
              ],
            )
            : SheetLabels(
              document: 'Packing list',
              from: 'Packer',
              to: 'Receiver',
              number: 'List',
              date: 'Date',
              extra: 'Crates',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Ordered',
                'Packed',
              ],
            ),
        number: 'PK-14',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? '3' : '3',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['حقيبة ميدانية', '12', '12']),
            SheetRow(<String>['صندوق تبريد', '4', '4']),
          ] : const <SheetRow>[
            SheetRow(<String>['Field kit', '12', '12']),
            SheetRow(<String>['Cold box', '4', '4']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'الرصيف الشمالي' : 'North Dock',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'commerce.price-list' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'الرصيف الشمالي' : 'North Dock',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'قائمة عامة' : 'Public list'),
        labels: arabic
            ? SheetLabels(
              document: 'قائمة أسعار',
              from: 'البائع',
              to: 'السوق',
              number: 'القائمة',
              date: 'التاريخ',
              extra: 'صالحة حتى',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'الرمز',
                'البند',
                'الوحدة',
                'السعر',
              ],
            )
            : SheetLabels(
              document: 'Price list',
              from: 'Seller',
              to: 'Market',
              number: 'List',
              date: 'Date',
              extra: 'Valid until',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'SKU',
                'Item',
                'Unit',
                'Price',
              ],
            ),
        number: 'PL-3',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? '31 كانون الأول 2026' : '31 Dec 2026',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['FK-1', 'حقيبة ميدانية', 'قطعة', '48']),
            SheetRow(<String>['CB-2', 'صندوق تبريد', 'قطعة', '90']),
          ] : const <SheetRow>[
            SheetRow(<String>['FK-1', 'Field kit', 'each', '48']),
            SheetRow(<String>['CB-2', 'Cold box', 'each', '90']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'الرصيف الشمالي' : 'North Dock',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'commerce.goods-received' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'الرصيف الشمالي' : 'North Dock',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'توريدات الميناء' : 'Harbour Supply'),
        labels: arabic
            ? SheetLabels(
              document: 'إذن استلام',
              from: 'المستلم',
              to: 'المورّد',
              number: 'الاستلام',
              date: 'التاريخ',
              extra: 'أمر الشراء',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'المطلوب',
                'المستلم',
              ],
            )
            : SheetLabels(
              document: 'Goods received',
              from: 'Receiver',
              to: 'Supplier',
              number: 'GRN',
              date: 'Date',
              extra: 'PO',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Ordered',
                'Received',
              ],
            ),
        number: 'GRN-6',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'PO-14' : 'PO-14',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['حقيبة ميدانية', '12', '12']),
            SheetRow(<String>['صندوق تبريد', '4', '3']),
          ] : const <SheetRow>[
            SheetRow(<String>['Field kit', '12', '12']),
            SheetRow(<String>['Cold box', '4', '3']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'صندوق تبريد ما زال على الشاحنة.' : 'One cold box is still on the truck.',
        footer: arabic ? 'الرصيف الشمالي' : 'North Dock',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'commerce.return' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'الرصيف الشمالي' : 'North Dock',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'عيادة النهر' : 'River Clinic'),
        labels: arabic
            ? SheetLabels(
              document: 'إذن مرتجع',
              from: 'البائع',
              to: 'المشتري',
              number: 'الإذن',
              date: 'التاريخ',
              extra: 'الفاتورة',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'الكمية',
                'السبب',
              ],
            )
            : SheetLabels(
              document: 'Return authorization',
              from: 'Seller',
              to: 'Buyer',
              number: 'RMA',
              date: 'Date',
              extra: 'Invoice',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Qty',
                'Reason',
              ],
            ),
        number: 'RMA-2',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'INV-14' : 'INV-14',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['صندوق تبريد', '1', 'غطاء مشقوق']),
            SheetRow(<String>['لفّة شاش', '2', 'عرض خاطئ']),
          ] : const <SheetRow>[
            SheetRow(<String>['Cold box', '1', 'Lid cracked']),
            SheetRow(<String>['Gauze roll', '2', 'Wrong width']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'الرصيف الشمالي' : 'North Dock',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'commerce.consignment' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'الرصيف الشمالي' : 'North Dock',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'عيادة النهر' : 'River Clinic'),
        labels: arabic
            ? SheetLabels(
              document: 'إذن أمانة',
              from: 'الحائز',
              to: 'المالك',
              number: 'الإذن',
              date: 'التاريخ',
              extra: 'الحفظ حتى',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'الكمية',
                'الحالة',
              ],
            )
            : SheetLabels(
              document: 'Consignment note',
              from: 'Holder',
              to: 'Owner',
              number: 'Note',
              date: 'Date',
              extra: 'Hold until',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Qty',
                'Condition',
              ],
            ),
        number: 'CS-1',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? '30 أيلول 2026' : '30 Sep 2026',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['هيكل خيمة', '2', 'جيد']),
            SheetRow(<String>['مصباح', '6', 'جيد']),
          ] : const <SheetRow>[
            SheetRow(<String>['Tent frame', '2', 'Good']),
            SheetRow(<String>['Lamp', '6', 'Good']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'الرصيف الشمالي' : 'North Dock',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'operations.goods-issue' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'الرصيف الشمالي' : 'North Dock',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'مسؤولو الأجنحة' : 'Ward leads'),
        labels: arabic
            ? SheetLabels(
              document: 'إذن صرف مواد',
              from: 'المستودع',
              to: 'الطالب',
              number: 'الصرف',
              date: 'التاريخ',
              extra: 'مركز الكلفة',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'الكمية',
                'الرف',
              ],
            )
            : SheetLabels(
              document: 'Goods issue',
              from: 'Store',
              to: 'Requester',
              number: 'Issue',
              date: 'Date',
              extra: 'Cost centre',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Qty',
                'Bin',
              ],
            ),
        number: 'GI-18',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'العيادة' : 'Clinic',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['قفازات', '10', 'A2']),
            SheetRow(<String>['كمامات', '20', 'A2']),
          ] : const <SheetRow>[
            SheetRow(<String>['Gloves', '10', 'A2']),
            SheetRow(<String>['Masks', '20', 'A2']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'الرصيف الشمالي' : 'North Dock',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'operations.inventory' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'الرصيف الشمالي' : 'North Dock',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'مستودع 4' : 'Warehouse 4'),
        labels: arabic
            ? SheetLabels(
              document: 'جرد',
              from: 'الجارد',
              to: 'المستودع',
              number: 'الجرد',
              date: 'التاريخ',
              extra: 'الممر',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'الدفتر',
                'المعدود',
              ],
            )
            : SheetLabels(
              document: 'Inventory count',
              from: 'Counter',
              to: 'Store',
              number: 'Count',
              date: 'Date',
              extra: 'Aisle',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Book',
                'Counted',
              ],
            ),
        number: 'IC-4',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'أ' : 'A',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['حقيبة ميدانية', '40', '39']),
            SheetRow(<String>['صندوق تبريد', '8', '8']),
          ] : const <SheetRow>[
            SheetRow(<String>['Field kit', '40', '39']),
            SheetRow(<String>['Cold box', '8', '8']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'الرصيف الشمالي' : 'North Dock',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'operations.assets' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'الرصيف الشمالي' : 'North Dock',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'عيادة النهر' : 'River Clinic'),
        labels: arabic
            ? SheetLabels(
              document: 'سجل أصول',
              from: 'السجل',
              to: 'الموقع',
              number: 'السجل',
              date: 'التاريخ',
              extra: 'الموقع',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'الوسم',
                'الأصل',
                'الحائز',
              ],
            )
            : SheetLabels(
              document: 'Asset register',
              from: 'Registry',
              to: 'Site',
              number: 'Register',
              date: 'Date',
              extra: 'Site',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Tag',
                'Asset',
                'Holder',
              ],
            ),
        number: 'AR-1',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'مستودع 4' : 'Warehouse 4',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['GT-2', 'محرّك البوابة', 'الورشة']),
            SheetRow(<String>['LT-9', 'صندوق تبريد', 'العيادة']),
          ] : const <SheetRow>[
            SheetRow(<String>['GT-2', 'Gate motor', 'Workshop']),
            SheetRow(<String>['LT-9', 'Cold box', 'Clinic']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'الرصيف الشمالي' : 'North Dock',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'operations.visitors' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'الرصيف الشمالي' : 'North Dock',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'عيادة النهر' : 'River Clinic'),
        labels: arabic
            ? SheetLabels(
              document: 'سجل زوار',
              from: 'البوابة',
              to: 'المضيف',
              number: 'السجل',
              date: 'التاريخ',
              extra: 'البوابة',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'الاسم',
                'الدخول',
                'المضيف',
              ],
            )
            : SheetLabels(
              document: 'Visitor log',
              from: 'Gate',
              to: 'Host',
              number: 'Log',
              date: 'Date',
              extra: 'Gate',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Name',
                'In',
                'Host',
              ],
            ),
        number: 'VL-14',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'الشرقية' : 'East',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['لينا حداد', '09:10', 'العيادة']),
            SheetRow(<String>['سامي ناصر', '11:40', 'الورشة']),
          ] : const <SheetRow>[
            SheetRow(<String>['Lina Haddad', '09:10', 'Clinic']),
            SheetRow(<String>['Sami Nasser', '11:40', 'Workshop']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'الرصيف الشمالي' : 'North Dock',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'operations.roster' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'الرصيف الشمالي' : 'North Dock',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'فريق الرصيف' : 'Dock team'),
        labels: arabic
            ? SheetLabels(
              document: 'جدول ورديات',
              from: 'المخطّط',
              to: 'الفريق',
              number: 'الجدول',
              date: 'التاريخ',
              extra: 'الأسبوع',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'الاسم',
                'النوبة',
                'الدور',
              ],
            )
            : SheetLabels(
              document: 'Shift roster',
              from: 'Planner',
              to: 'Team',
              number: 'Roster',
              date: 'Date',
              extra: 'Week',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Name',
                'Watch',
                'Role',
              ],
            ),
        number: 'SR-37',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'الأسبوع 37' : 'Week 37',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['لينا حداد', 'فجر', 'عيادة']),
            SheetRow(<String>['سامي ناصر', 'ليل', 'بوابة']),
          ] : const <SheetRow>[
            SheetRow(<String>['Lina Haddad', 'Dawn', 'Clinic']),
            SheetRow(<String>['Sami Nasser', 'Night', 'Gate']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'الرصيف الشمالي' : 'North Dock',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'operations.ticket' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'الرصيف الشمالي' : 'North Dock',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'عيادة النهر' : 'River Clinic'),
        labels: arabic
            ? SheetLabels(
              document: 'تذكرة خدمة',
              from: 'المكتب',
              to: 'الموقع',
              number: 'التذكرة',
              date: 'التاريخ',
              extra: 'الأولوية',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'المهمة',
                'الصاحب',
                'الحالة',
              ],
            )
            : SheetLabels(
              document: 'Service ticket',
              from: 'Desk',
              to: 'Site',
              number: 'Ticket',
              date: 'Date',
              extra: 'Priority',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Task',
                'Owner',
                'Status',
              ],
            ),
        number: 'TK-55',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'عالية' : 'High',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['إنارة شرقية', 'الورشة', 'مفتوح']),
            SheetRow(<String>['سلسلة تبريد', 'العيادة', 'تم']),
          ] : const <SheetRow>[
            SheetRow(<String>['East light', 'Workshop', 'Open']),
            SheetRow(<String>['Cold chain', 'Clinic', 'Done']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'الرصيف الشمالي' : 'North Dock',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'logistics.pick-list' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'الرصيف الشمالي' : 'North Dock',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'SO-88' : 'SO-88'),
        labels: arabic
            ? SheetLabels(
              document: 'قائمة تجهيز',
              from: 'المستودع',
              to: 'الطلب',
              number: 'التجهيز',
              date: 'التاريخ',
              extra: 'الرصيف',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'الرف',
                'البند',
                'الكمية',
              ],
            )
            : SheetLabels(
              document: 'Pick list',
              from: 'Warehouse',
              to: 'Order',
              number: 'Pick',
              date: 'Date',
              extra: 'Bay',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Bin',
                'Item',
                'Qty',
              ],
            ),
        number: 'PKL-8',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'الرصيف 2' : 'Bay 2',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['A2', 'قفازات', '10']),
            SheetRow(<String>['B1', 'حقيبة ميدانية', '12']),
          ] : const <SheetRow>[
            SheetRow(<String>['A2', 'Gloves', '10']),
            SheetRow(<String>['B1', 'Field kit', '12']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'الرصيف الشمالي' : 'North Dock',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'logistics.manifest' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'الرصيف الشمالي' : 'North Dock',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'الجولة 4' : 'Run 4'),
        labels: arabic
            ? SheetLabels(
              document: 'بيان تسليم',
              from: 'الموزّع',
              to: 'السائق',
              number: 'الجولة',
              date: 'التاريخ',
              extra: 'المركبة',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'المحطة',
                'المكان',
                'الصناديق',
              ],
            )
            : SheetLabels(
              document: 'Delivery manifest',
              from: 'Dispatcher',
              to: 'Driver',
              number: 'Run',
              date: 'Date',
              extra: 'Vehicle',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Stop',
                'Place',
                'Crates',
              ],
            ),
        number: 'DM-4',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'فان 2' : 'Van 2',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['1', 'عيادة النهر', '3']),
            SheetRow(<String>['2', 'بوابة المدرسة', '1']),
          ] : const <SheetRow>[
            SheetRow(<String>['1', 'River Clinic', '3']),
            SheetRow(<String>['2', 'School gate', '1']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'الرصيف الشمالي' : 'North Dock',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'logistics.waybill' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'مستودع 4' : 'Warehouse 4',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'عيادة النهر' : 'River Clinic'),
        labels: arabic
            ? SheetLabels(
              document: 'بوليصة نقل',
              from: 'المنشأ',
              to: 'الوجهة',
              number: 'البوليصة',
              date: 'التاريخ',
              extra: 'السائق',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'الكمية',
                'العلامات',
              ],
            )
            : SheetLabels(
              document: 'Waybill',
              from: 'Origin',
              to: 'Destination',
              number: 'Waybill',
              date: 'Date',
              extra: 'Driver',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Qty',
                'Marks',
              ],
            ),
        number: 'WB-17',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'الجولة 4' : 'Run 4',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['حقيبة ميدانية', '12', 'ND-12']),
            SheetRow(<String>['صندوق تبريد', '4', 'ND-4']),
          ] : const <SheetRow>[
            SheetRow(<String>['Field kit', '12', 'ND-12']),
            SheetRow(<String>['Cold box', '4', 'ND-4']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'مستودع 4' : 'Warehouse 4',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'logistics.transfer' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'مستودع 4' : 'Warehouse 4',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'مخزن العيادة' : 'Clinic store'),
        labels: arabic
            ? SheetLabels(
              document: 'تحويل مستودع',
              from: 'من مستودع',
              to: 'إلى مستودع',
              number: 'التحويل',
              date: 'التاريخ',
              extra: 'السبب',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'الكمية',
                'من رف',
              ],
            )
            : SheetLabels(
              document: 'Warehouse transfer',
              from: 'From store',
              to: 'To store',
              number: 'Transfer',
              date: 'Date',
              extra: 'Reason',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Qty',
                'From bin',
              ],
            ),
        number: 'WT-3',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'عيادة الليل' : 'Night clinic',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['قفازات', '10', 'A2']),
            SheetRow(<String>['كمامات', '20', 'A2']),
          ] : const <SheetRow>[
            SheetRow(<String>['Gloves', '10', 'A2']),
            SheetRow(<String>['Masks', '20', 'A2']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'مستودع 4' : 'Warehouse 4',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'logistics.load-sheet' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'الرصيف الشمالي' : 'North Dock',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'فان 2' : 'Van 2'),
        labels: arabic
            ? SheetLabels(
              document: 'كشف تحميل',
              from: 'الرصيف',
              to: 'المركبة',
              number: 'التحميل',
              date: 'التاريخ',
              extra: 'الباب',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'الترتيب',
                'البند',
                'الكمية',
              ],
            )
            : SheetLabels(
              document: 'Load sheet',
              from: 'Bay',
              to: 'Vehicle',
              number: 'Load',
              date: 'Date',
              extra: 'Door',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Order',
                'Item',
                'Qty',
              ],
            ),
        number: 'LS-4',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'الخلفي' : 'Rear',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['1', 'صندوق تبريد', '4']),
            SheetRow(<String>['2', 'حقيبة ميدانية', '12']),
          ] : const <SheetRow>[
            SheetRow(<String>['1', 'Cold box', '4']),
            SheetRow(<String>['2', 'Field kit', '12']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'الرصيف الشمالي' : 'North Dock',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'logistics.notice' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'الرصيف الشمالي' : 'North Dock',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'عيادة النهر' : 'River Clinic'),
        labels: arabic
            ? SheetLabels(
              document: 'إشعار شحن',
              from: 'المرسل',
              to: 'المستلم',
              number: 'الإشعار',
              date: 'التاريخ',
              extra: 'الوصول',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'الكمية',
                'العلامات',
              ],
            )
            : SheetLabels(
              document: 'Shipping notice',
              from: 'Sender',
              to: 'Receiver',
              number: 'Notice',
              date: 'Date',
              extra: 'ETA',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Qty',
                'Marks',
              ],
            ),
        number: 'SN-9',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? '15 أيلول 09:00' : '15 Sep 09:00',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['حقيبة ميدانية', '12', 'ND-12']),
            SheetRow(<String>['لفّة شاش', '20', 'GZ-20']),
          ] : const <SheetRow>[
            SheetRow(<String>['Field kit', '12', 'ND-12']),
            SheetRow(<String>['Gauze roll', '20', 'GZ-20']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'الرصيف الشمالي' : 'North Dock',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'people.attendance' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'الرصيف الشمالي' : 'North Dock',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'الفجر' : 'Dawn'),
        labels: arabic
            ? SheetLabels(
              document: 'كشف حضور',
              from: 'الفريق',
              to: 'الوردية',
              number: 'الكشف',
              date: 'التاريخ',
              extra: 'الوردية',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'الاسم',
                'الدخول',
                'العلامة',
              ],
            )
            : SheetLabels(
              document: 'Attendance sheet',
              from: 'Team',
              to: 'Shift',
              number: 'Sheet',
              date: 'Date',
              extra: 'Shift',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Name',
                'In',
                'Mark',
              ],
            ),
        number: 'AT-14',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'الفجر' : 'Dawn',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['لينا حداد', '05:50', 'حاضر']),
            SheetRow(<String>['سامي ناصر', '—', 'إجازة']),
          ] : const <SheetRow>[
            SheetRow(<String>['Lina Haddad', '05:50', 'Present']),
            SheetRow(<String>['Sami Nasser', '—', 'Leave']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'الرصيف الشمالي' : 'North Dock',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'education.register' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'مدرسة النهر' : 'River School',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'هدى صالح' : 'Huda Saleh'),
        labels: arabic
            ? SheetLabels(
              document: 'سجل صف',
              from: 'الصف',
              to: 'المعلّم',
              number: 'السجل',
              date: 'التاريخ',
              extra: 'الصف',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'الاسم',
                'العلامة',
                'ملاحظة',
              ],
            )
            : SheetLabels(
              document: 'Class register',
              from: 'Class',
              to: 'Teacher',
              number: 'Register',
              date: 'Date',
              extra: 'Class',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Name',
                'Mark',
                'Note',
              ],
            ),
        number: 'CR-3',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'الصف الثالث' : 'Form 3',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['لينا حداد', 'حاضر', '']),
            SheetRow(<String>['عمر ناصر', 'متأخر', 'البوابة']),
          ] : const <SheetRow>[
            SheetRow(<String>['Lina Haddad', 'Present', '']),
            SheetRow(<String>['Omar Nasser', 'Late', 'Gate']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'مدرسة النهر' : 'River School',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'education.transcript' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'مدرسة النهر' : 'River School',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'لينا حداد' : 'Lina Haddad'),
        labels: arabic
            ? SheetLabels(
              document: 'سجل أكاديمي',
              from: 'المدرسة',
              to: 'الطالب',
              number: 'السجل',
              date: 'التاريخ',
              extra: 'السنة',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'المادة',
                'الدرجة',
                'التقدير',
              ],
            )
            : SheetLabels(
              document: 'Transcript',
              from: 'School',
              to: 'Student',
              number: 'Record',
              date: 'Date',
              extra: 'Year',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Subject',
                'Mark',
                'Grade',
              ],
            ),
        number: 'TR-19',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? '2026' : '2026',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['العربية', '88', 'أ']),
            SheetRow(<String>['العلوم', '76', 'ب']),
          ] : const <SheetRow>[
            SheetRow(<String>['Arabic', '88', 'A']),
            SheetRow(<String>['Science', '76', 'B']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'مدرسة النهر' : 'River School',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'education.report-card' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'مدرسة النهر' : 'River School',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'لينا حداد' : 'Lina Haddad'),
        labels: arabic
            ? SheetLabels(
              document: 'كشف درجات',
              from: 'المدرسة',
              to: 'الطالب',
              number: 'الكشف',
              date: 'التاريخ',
              extra: 'الفصل',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'المادة',
                'الدرجة',
                'التعليق',
              ],
            )
            : SheetLabels(
              document: 'Report card',
              from: 'School',
              to: 'Student',
              number: 'Card',
              date: 'Date',
              extra: 'Term',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Subject',
                'Mark',
                'Comment',
              ],
            ),
        number: 'RC-3',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'الخريف' : 'Autumn',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['العربية', '88', 'واضح']),
            SheetRow(<String>['العلوم', '76', 'ثابت']),
          ] : const <SheetRow>[
            SheetRow(<String>['Arabic', '88', 'Clear']),
            SheetRow(<String>['Science', '76', 'Steady']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'مدرسة النهر' : 'River School',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'property.listing' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'إسكان الرصيف' : 'Dock Housing',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'طريق الميناء' : 'Port Road'),
        labels: arabic
            ? SheetLabels(
              document: 'عرض عقار',
              from: 'المكتب',
              to: 'المنطقة',
              number: 'العرض',
              date: 'التاريخ',
              extra: 'المنطقة',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'الوحدة',
                'الإيجار',
                'الحالة',
              ],
            )
            : SheetLabels(
              document: 'Property listing',
              from: 'Office',
              to: 'Area',
              number: 'List',
              date: 'Date',
              extra: 'Area',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Unit',
                'Rent',
                'Status',
              ],
            ),
        number: 'HL-2',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'طريق الميناء' : 'Port Road',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['4B', '650', 'مؤجّرة']),
            SheetRow(<String>['4C', '640', 'شاغرة']),
          ] : const <SheetRow>[
            SheetRow(<String>['4B', '650', 'Let']),
            SheetRow(<String>['4C', '640', 'Open']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'إسكان الرصيف' : 'Dock Housing',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'programs.beneficiaries' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'صندوق النهر' : 'River Fund',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'الجناح ب' : 'Ward B'),
        labels: arabic
            ? SheetLabels(
              document: 'كشف مستفيدين',
              from: 'البرنامج',
              to: 'الموقع',
              number: 'الكشف',
              date: 'التاريخ',
              extra: 'الجولة',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'الاسم',
                'الحصة',
                'العلامة',
              ],
            )
            : SheetLabels(
              document: 'Beneficiary list',
              from: 'Program',
              to: 'Site',
              number: 'List',
              date: 'Date',
              extra: 'Round',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Name',
                'Share',
                'Mark',
              ],
            ),
        number: 'BL-6',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'الجولة 2' : 'Round 2',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['عائلة حداد', 'حقيبة', 'مستحق']),
            SheetRow(<String>['ناصر', 'حقيبة', 'صُرف']),
          ] : const <SheetRow>[
            SheetRow(<String>['Haddad family', '1 kit', 'Due']),
            SheetRow(<String>['Nasser', '1 kit', 'Given']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'صندوق النهر' : 'River Fund',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'programs.distribution' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'صندوق النهر' : 'River Fund',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'الجولة 2' : 'Round 2'),
        labels: arabic
            ? SheetLabels(
              document: 'كشف توزيع',
              from: 'الفريق',
              to: 'الجولة',
              number: 'الكشف',
              date: 'التاريخ',
              extra: 'الموقع',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'الأسرة',
                'البند',
                'الكمية',
              ],
            )
            : SheetLabels(
              document: 'Distribution sheet',
              from: 'Team',
              to: 'Round',
              number: 'Sheet',
              date: 'Date',
              extra: 'Site',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Household',
                'Item',
                'Qty',
              ],
            ),
        number: 'FD-2',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'الجناح ب' : 'Ward B',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['حداد', 'حقيبة', '1']),
            SheetRow(<String>['ناصر', 'بطانية', '2']),
          ] : const <SheetRow>[
            SheetRow(<String>['Haddad', 'Kit', '1']),
            SheetRow(<String>['Nasser', 'Blanket', '2']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'صندوق النهر' : 'River Fund',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'programs.workshop' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'صندوق النهر' : 'River Fund',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'سلسلة التبريد' : 'Cold chain'),
        labels: arabic
            ? SheetLabels(
              document: 'سجل ورشة',
              from: 'المضيف',
              to: 'الجلسة',
              number: 'الجلسة',
              date: 'التاريخ',
              extra: 'القاعة',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'الاسم',
                'الدور',
                'العلامة',
              ],
            )
            : SheetLabels(
              document: 'Workshop register',
              from: 'Host',
              to: 'Session',
              number: 'Session',
              date: 'Date',
              extra: 'Room',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Name',
                'Role',
                'Mark',
              ],
            ),
        number: 'WS-3',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'القاعة' : 'Hall',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['لينا حداد', 'تمريض', 'حاضر']),
            SheetRow(<String>['سامي ناصر', 'بوابة', 'حاضر']),
          ] : const <SheetRow>[
            SheetRow(<String>['Lina Haddad', 'Nurse', 'Present']),
            SheetRow(<String>['Sami Nasser', 'Gate', 'Present']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'صندوق النهر' : 'River Fund',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'programs.volunteers' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'صندوق النهر' : 'River Fund',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'أيلول' : 'September'),
        labels: arabic
            ? SheetLabels(
              document: 'ساعات تطوع',
              from: 'البرنامج',
              to: 'الفترة',
              number: 'الكشف',
              date: 'التاريخ',
              extra: 'الفترة',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'الاسم',
                'الساعات',
                'المهمة',
              ],
            )
            : SheetLabels(
              document: 'Volunteer hours',
              from: 'Program',
              to: 'Period',
              number: 'Sheet',
              date: 'Date',
              extra: 'Period',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Name',
                'Hours',
                'Task',
              ],
            ),
        number: 'VH-9',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'أيلول' : 'September',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['لينا حداد', '12', 'عيادة']),
            SheetRow(<String>['عمر ناصر', '6', 'بوابة']),
          ] : const <SheetRow>[
            SheetRow(<String>['Lina Haddad', '12', 'Clinic']),
            SheetRow(<String>['Omar Nasser', '6', 'Gate']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'صندوق النهر' : 'River Fund',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'data.timesheet' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'سامي ناصر' : 'Sami Nasser',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'الأسبوع 37' : 'Week 37'),
        labels: arabic
            ? SheetLabels(
              document: 'كشف ساعات',
              from: 'العامل',
              to: 'الفترة',
              number: 'الكشف',
              date: 'التاريخ',
              extra: 'الأسبوع',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'اليوم',
                'الساعات',
                'المشروع',
              ],
            )
            : SheetLabels(
              document: 'Timesheet',
              from: 'Worker',
              to: 'Period',
              number: 'Sheet',
              date: 'Date',
              extra: 'Week',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Day',
                'Hours',
                'Project',
              ],
            ),
        number: 'TS-37',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'الأسبوع 37' : 'Week 37',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['الإثنين', '8', 'البوابة']),
            SheetRow(<String>['الثلاثاء', '7', 'العيادة']),
          ] : const <SheetRow>[
            SheetRow(<String>['Mon', '8', 'Gate']),
            SheetRow(<String>['Tue', '7', 'Clinic']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'سامي ناصر' : 'Sami Nasser',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'data.milestones' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'عيادة الليل' : 'Night clinic',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'التشغيل' : 'Operations'),
        labels: arabic
            ? SheetLabels(
              document: 'متتبع معالم',
              from: 'المشروع',
              to: 'الصاحب',
              number: 'المتتبّع',
              date: 'التاريخ',
              extra: 'المرحلة',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'المعلم',
                'الاستحقاق',
                'الحالة',
              ],
            )
            : SheetLabels(
              document: 'Milestone tracker',
              from: 'Project',
              to: 'Owner',
              number: 'Tracker',
              date: 'Date',
              extra: 'Phase',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Milestone',
                'Due',
                'Status',
              ],
            ),
        number: 'MS-2',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'التجهيز' : 'Fit-out',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['الكهرباء', '12 أيلول', 'تم']),
            SheetRow(<String>['غرفة التبريد', '20 أيلول', 'مفتوح']),
          ] : const <SheetRow>[
            SheetRow(<String>['Power', '12 Sep', 'Done']),
            SheetRow(<String>['Cold room', '20 Sep', 'Open']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'عيادة الليل' : 'Night clinic',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'data.risks' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'عيادة الليل' : 'Night clinic',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'أيلول' : 'September'),
        labels: arabic
            ? SheetLabels(
              document: 'سجل مخاطر',
              from: 'المشروع',
              to: 'المراجعة',
              number: 'السجل',
              date: 'التاريخ',
              extra: 'المراجعة',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'المخاطرة',
                'الصاحب',
                'التقدير',
              ],
            )
            : SheetLabels(
              document: 'Risk register',
              from: 'Project',
              to: 'Review',
              number: 'Register',
              date: 'Date',
              extra: 'Review',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Risk',
                'Owner',
                'Rating',
              ],
            ),
        number: 'RK-1',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'أيلول' : 'September',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['انقطاع كهرباء', 'الورشة', 'عالٍ']),
            SheetRow(<String>['تأخّر الحقائب', 'الرصيف', 'متوسط']),
          ] : const <SheetRow>[
            SheetRow(<String>['Power cut', 'Workshop', 'High']),
            SheetRow(<String>['Late kits', 'Dock', 'Medium']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'عيادة الليل' : 'Night clinic',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'data.issues' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'التشغيل' : 'Operations',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'الأسبوع 37' : 'Week 37'),
        labels: arabic
            ? SheetLabels(
              document: 'سجل مشكلات',
              from: 'المكتب',
              to: 'الأسبوع',
              number: 'السجل',
              date: 'التاريخ',
              extra: 'الأسبوع',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'المشكلة',
                'الصاحب',
                'الحالة',
              ],
            )
            : SheetLabels(
              document: 'Issue log',
              from: 'Desk',
              to: 'Week',
              number: 'Log',
              date: 'Date',
              extra: 'Week',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Issue',
                'Owner',
                'Status',
              ],
            ),
        number: 'IL-37',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'الأسبوع 37' : 'Week 37',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['إنارة شرقية', 'الورشة', 'مفتوح']),
            SheetRow(<String>['صندوق ناقص', 'الرصيف', 'متابعة']),
          ] : const <SheetRow>[
            SheetRow(<String>['East light', 'Workshop', 'Open']),
            SheetRow(<String>['Short crate', 'Dock', 'Watching']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'التشغيل' : 'Operations',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'data.comparison' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'التشغيل' : 'Operations',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'صناديق التبريد' : 'Cold boxes'),
        labels: arabic
            ? SheetLabels(
              document: 'مقارنة',
              from: 'الكاتب',
              to: 'الخيار',
              number: 'المذكرة',
              date: 'التاريخ',
              extra: 'الخيار',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'النقطة',
                'الصندوق',
                'الصندوق الكبير',
              ],
            )
            : SheetLabels(
              document: 'Comparison',
              from: 'Author',
              to: 'Choice',
              number: 'Note',
              date: 'Date',
              extra: 'Choice',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Point',
                'Crate',
                'Chest',
              ],
            ),
        number: 'CP-1',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'صناديق التبريد' : 'Cold boxes',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['السعر', '90', '140']),
            SheetRow(<String>['الطاقة', 'بلا', 'كهرباء']),
          ] : const <SheetRow>[
            SheetRow(<String>['Price', '90', '140']),
            SheetRow(<String>['Power', 'None', 'Mains']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'التشغيل' : 'Operations',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'data.leaderboard' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'دوري العيادة' : 'Clinic league',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'أيلول' : 'September'),
        labels: arabic
            ? SheetLabels(
              document: 'لوحة ترتيب',
              from: 'اللوحة',
              to: 'الفترة',
              number: 'اللوحة',
              date: 'التاريخ',
              extra: 'الفترة',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'الترتيب',
                'الاسم',
                'النتيجة',
              ],
            )
            : SheetLabels(
              document: 'Leaderboard',
              from: 'Board',
              to: 'Period',
              number: 'Board',
              date: 'Date',
              extra: 'Period',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Rank',
                'Name',
                'Score',
              ],
            ),
        number: 'LB-9',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'أيلول' : 'September',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['1', 'لينا حداد', '98']),
            SheetRow(<String>['2', 'سامي ناصر', '91']),
          ] : const <SheetRow>[
            SheetRow(<String>['1', 'Lina Haddad', '98']),
            SheetRow(<String>['2', 'Sami Nasser', '91']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'دوري العيادة' : 'Clinic league',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'data.exceptions' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'التشغيل' : 'Operations',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'حقائب في موعدها' : 'On-time kits'),
        labels: arabic
            ? SheetLabels(
              document: 'تقرير استثناءات',
              from: 'المكتب',
              to: 'القاعدة',
              number: 'التقرير',
              date: 'التاريخ',
              extra: 'القاعدة',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'الحالة',
                'المتوقع',
                'الفعلي',
              ],
            )
            : SheetLabels(
              document: 'Exception report',
              from: 'Desk',
              to: 'Rule',
              number: 'Report',
              date: 'Date',
              extra: 'Rule',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Case',
                'Expected',
                'Actual',
              ],
            ),
        number: 'EX-3',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'حقائب في موعدها' : 'On-time kits',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['SO-88', '20 أيلول', 'متأخر']),
            SheetRow(<String>['GRN-6', '4 صناديق', '3 صناديق']),
          ] : const <SheetRow>[
            SheetRow(<String>['SO-88', '20 Sep', 'Late']),
            SheetRow(<String>['GRN-6', '4 boxes', '3 boxes']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'التشغيل' : 'Operations',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'finance.profit-loss' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'الرصيف الشمالي' : 'North Dock',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'أيلول' : 'September'),
        labels: arabic
            ? SheetLabels(
              document: 'الأرباح والخسائر',
              from: 'الجهة',
              to: 'الفترة',
              number: 'القائمة',
              date: 'التاريخ',
              extra: 'الفترة',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'النوع',
                'المبلغ',
              ],
            )
            : SheetLabels(
              document: 'Profit and loss',
              from: 'Entity',
              to: 'Period',
              number: 'Statement',
              date: 'Date',
              extra: 'Period',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Line',
                'Kind',
                'Amount',
              ],
            ),
        number: 'PL-9',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'أيلول' : 'September',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['بيع الحقائب', 'إيراد', '1,076']),
            SheetRow(<String>['أجور', 'تكلفة', '640']),
          ] : const <SheetRow>[
            SheetRow(<String>['Kit sales', 'Income', '1,076']),
            SheetRow(<String>['Wages', 'Cost', '640']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'الرصيف الشمالي' : 'North Dock',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'finance.balance' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'الرصيف الشمالي' : 'North Dock',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? '14 أيلول 2026' : '14 Sep 2026'),
        labels: arabic
            ? SheetLabels(
              document: 'ملخص الميزانية',
              from: 'الجهة',
              to: 'كما في',
              number: 'الملخص',
              date: 'التاريخ',
              extra: 'كما في',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'الجانب',
                'المبلغ',
              ],
            )
            : SheetLabels(
              document: 'Balance snapshot',
              from: 'Entity',
              to: 'As of',
              number: 'Snapshot',
              date: 'Date',
              extra: 'As of',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Line',
                'Side',
                'Amount',
              ],
            ),
        number: 'BS-14',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['نقد', 'أصل', '2,400']),
            SheetRow(<String>['دائنون', 'خصم', '470']),
          ] : const <SheetRow>[
            SheetRow(<String>['Cash', 'Asset', '2,400']),
            SheetRow(<String>['Payables', 'Liability', '470']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'الرصيف الشمالي' : 'North Dock',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'finance.cash-flow' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'الرصيف الشمالي' : 'North Dock',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'أيلول' : 'September'),
        labels: arabic
            ? SheetLabels(
              document: 'التدفق النقدي',
              from: 'الجهة',
              to: 'الفترة',
              number: 'التدفق',
              date: 'التاريخ',
              extra: 'الفترة',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'الاتجاه',
                'المبلغ',
              ],
            )
            : SheetLabels(
              document: 'Cash flow',
              from: 'Entity',
              to: 'Period',
              number: 'Flow',
              date: 'Date',
              extra: 'Period',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Line',
                'Way',
                'Amount',
              ],
            ),
        number: 'CF-9',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'أيلول' : 'September',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['مقبوضات الحقائب', 'داخل', '868']),
            SheetRow(<String>['سند PV-31', 'خارج', '470']),
          ] : const <SheetRow>[
            SheetRow(<String>['Kit receipts', 'In', '868']),
            SheetRow(<String>['Voucher PV-31', 'Out', '470']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'الرصيف الشمالي' : 'North Dock',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'finance.budget-actual' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'الرصيف الشمالي' : 'North Dock',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'الربع الثالث' : 'Q3'),
        labels: arabic
            ? SheetLabels(
              document: 'الميزانية مقابل الفعلي',
              from: 'الجهة',
              to: 'الفترة',
              number: 'الورقة',
              date: 'التاريخ',
              extra: 'الفترة',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'الخطة',
                'الفعلي',
                'الفرق',
              ],
            )
            : SheetLabels(
              document: 'Budget versus actual',
              from: 'Entity',
              to: 'Period',
              number: 'Sheet',
              date: 'Date',
              extra: 'Period',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Line',
                'Plan',
                'Actual',
                'Variance',
              ],
            ),
        number: 'BA-3',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'الربع الثالث' : 'Q3',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['الحقائب', '1,000', '1,076', '+76']),
            SheetRow(<String>['الأجور', '700', '640', '-60']),
          ] : const <SheetRow>[
            SheetRow(<String>['Kits', '1,000', '1,076', '+76']),
            SheetRow(<String>['Wages', '700', '640', '-60']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'الرصيف الشمالي' : 'North Dock',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'finance.aged-receivables' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'الرصيف الشمالي' : 'North Dock',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? '14 أيلول 2026' : '14 Sep 2026'),
        labels: arabic
            ? SheetLabels(
              document: 'أعمار الذمم المدينة',
              from: 'الجهة',
              to: 'كما في',
              number: 'الأعمار',
              date: 'التاريخ',
              extra: 'كما في',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'الحساب',
                'جاري',
                '30 يوماً',
                '60 يوماً',
              ],
            )
            : SheetLabels(
              document: 'Aged receivables',
              from: 'Entity',
              to: 'As of',
              number: 'Aging',
              date: 'Date',
              extra: 'As of',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Account',
                'Current',
                '30 days',
                '60 days',
              ],
            ),
        number: 'AR-14',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['عيادة النهر', '200', '0', '0']),
            SheetRow(<String>['المدرسة', '0', '60', '0']),
          ] : const <SheetRow>[
            SheetRow(<String>['River Clinic', '200', '0', '0']),
            SheetRow(<String>['School', '0', '60', '0']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'الرصيف الشمالي' : 'North Dock',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'finance.aged-payables' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'الرصيف الشمالي' : 'North Dock',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? '14 أيلول 2026' : '14 Sep 2026'),
        labels: arabic
            ? SheetLabels(
              document: 'أعمار الذمم الدائنة',
              from: 'الجهة',
              to: 'كما في',
              number: 'الأعمار',
              date: 'التاريخ',
              extra: 'كما في',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'المورّد',
                'جاري',
                '30 يوماً',
                '60 يوماً',
              ],
            )
            : SheetLabels(
              document: 'Aged payables',
              from: 'Entity',
              to: 'As of',
              number: 'Aging',
              date: 'Date',
              extra: 'As of',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Supplier',
                'Current',
                '30 days',
                '60 days',
              ],
            ),
        number: 'AP-14',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['توريدات الميناء', '360', '0', '0']),
            SheetRow(<String>['شحن الساحل', '180', '0', '0']),
          ] : const <SheetRow>[
            SheetRow(<String>['Harbour Supply', '360', '0', '0']),
            SheetRow(<String>['Coast Freight', '180', '0', '0']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'الرصيف الشمالي' : 'North Dock',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'finance.journal' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'الرصيف الشمالي' : 'North Dock',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? '14 أيلول 2026' : '14 Sep 2026'),
        labels: arabic
            ? SheetLabels(
              document: 'قيد يومية',
              from: 'الدفتر',
              to: 'اليوم',
              number: 'القيد',
              date: 'التاريخ',
              extra: 'اليوم',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'الحساب',
                'البيان',
                'مدين',
                'دائن',
              ],
            )
            : SheetLabels(
              document: 'Journal',
              from: 'Book',
              to: 'Day',
              number: 'Entry',
              date: 'Date',
              extra: 'Day',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Account',
                'Detail',
                'Debit',
                'Credit',
              ],
            ),
        number: 'JE-40',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['نقد', 'عربون الحقائب', '200', '']),
            SheetRow(<String>['مبيعات', 'عربون الحقائب', '', '200']),
          ] : const <SheetRow>[
            SheetRow(<String>['Cash', 'Kit deposit', '200', '']),
            SheetRow(<String>['Sales', 'Kit deposit', '', '200']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'الرصيف الشمالي' : 'North Dock',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'finance.petty-cash' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'الرصيف الشمالي' : 'North Dock',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'صندوق البوابة' : 'Gate box'),
        labels: arabic
            ? SheetLabels(
              document: 'صندوق النثرية',
              from: 'الأمين',
              to: 'الصندوق',
              number: 'الدفتر',
              date: 'التاريخ',
              extra: 'الصندوق',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'التاريخ',
                'البيان',
                'خارج',
                'الرصيد',
              ],
            )
            : SheetLabels(
              document: 'Petty cash',
              from: 'Custodian',
              to: 'Box',
              number: 'Book',
              date: 'Date',
              extra: 'Box',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Date',
                'Detail',
                'Out',
                'Balance',
              ],
            ),
        number: 'PC-2',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'صندوق البوابة' : 'Gate box',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['12 أيلول', 'لمبات', '18', '82']),
            SheetRow(<String>['13 أيلول', 'شريط', '6', '76']),
          ] : const <SheetRow>[
            SheetRow(<String>['12 Sep', 'Bulbs', '18', '82']),
            SheetRow(<String>['13 Sep', 'Tape', '6', '76']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'الرصيف الشمالي' : 'North Dock',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'finance.loan-schedule' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'ائتمان الميناء' : 'Harbour Credit',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'الرصيف الشمالي' : 'North Dock'),
        labels: arabic
            ? SheetLabels(
              document: 'جدول سداد',
              from: 'المقرض',
              to: 'المقترض',
              number: 'القرض',
              date: 'التاريخ',
              extra: 'ملاحظة النسبة',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'الاستحقاق',
                'الأصل',
                'الكلفة',
                'الرصيد',
              ],
            )
            : SheetLabels(
              document: 'Loan schedule',
              from: 'Lender',
              to: 'Borrower',
              number: 'Loan',
              date: 'Date',
              extra: 'Rate note',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Due',
                'Principal',
                'Charge',
                'Balance',
              ],
            ),
        number: 'LN-1',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'ملاحظة ثابتة' : 'Fixed note',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['أيلول', '200', '20', '800']),
            SheetRow(<String>['تشرين الأول', '200', '18', '600']),
          ] : const <SheetRow>[
            SheetRow(<String>['Sep', '200', '20', '800']),
            SheetRow(<String>['Oct', '200', '18', '600']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'ائتمان الميناء' : 'Harbour Credit',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'finance.reconciliation' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'الرصيف الشمالي' : 'North Dock',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'ائتمان الميناء' : 'Harbour Credit'),
        labels: arabic
            ? SheetLabels(
              document: 'تسوية بنكية',
              from: 'الدفتر',
              to: 'البنك',
              number: 'التسوية',
              date: 'التاريخ',
              extra: 'كما في',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'الدفتر',
                'البنك',
              ],
            )
            : SheetLabels(
              document: 'Bank reconciliation',
              from: 'Book',
              to: 'Bank',
              number: 'Reconcile',
              date: 'Date',
              extra: 'As of',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Book',
                'Bank',
              ],
            ),
        number: 'BR-9',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['افتتاحي', '1,200', '1,200']),
            SheetRow(<String>['سند لم يُصرف', '470', '0']),
          ] : const <SheetRow>[
            SheetRow(<String>['Opening', '1,200', '1,200']),
            SheetRow(<String>['PV-31 not cleared', '470', '0']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'الرصيف الشمالي' : 'North Dock',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'finance.tax-summary' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'الرصيف الشمالي' : 'North Dock',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'الربع الثالث' : 'Q3'),
        labels: arabic
            ? SheetLabels(
              document: 'ملخص ضريبة',
              from: 'الجهة',
              to: 'الفترة',
              number: 'الملخص',
              date: 'التاريخ',
              extra: 'الفترة',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'الشريحة',
                'الأساس',
                'الضريبة',
              ],
            )
            : SheetLabels(
              document: 'Tax summary',
              from: 'Entity',
              to: 'Period',
              number: 'Summary',
              date: 'Date',
              extra: 'Period',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Bucket',
                'Base',
                'Tax',
              ],
            ),
        number: 'TX-3',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'الربع الثالث' : 'Q3',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['الحقائب', '936', '140']),
            SheetRow(<String>['الخدمات', '330', '50']),
          ] : const <SheetRow>[
            SheetRow(<String>['Kits', '936', '140']),
            SheetRow(<String>['Services', '330', '50']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'هذا ملخص عمل وليس إقراراً ضريبياً.' : 'This is a working summary, not a tax return.',
        footer: arabic ? 'الرصيف الشمالي' : 'North Dock',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'finance.payroll-summary' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'الرصيف الشمالي' : 'North Dock',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'أيلول' : 'September'),
        labels: arabic
            ? SheetLabels(
              document: 'ملخص رواتب',
              from: 'صاحب العمل',
              to: 'الفترة',
              number: 'المسير',
              date: 'التاريخ',
              extra: 'الفترة',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'الشريحة',
                'العدد',
                'الصافي',
              ],
            )
            : SheetLabels(
              document: 'Payroll summary',
              from: 'Employer',
              to: 'Period',
              number: 'Run',
              date: 'Date',
              extra: 'Period',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Band',
                'Headcount',
                'Net',
              ],
            ),
        number: 'PR-9',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'أيلول' : 'September',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['العيادة', '4', '3,200']),
            SheetRow(<String>['البوابة', '2', '1,400']),
          ] : const <SheetRow>[
            SheetRow(<String>['Clinic', '4', '3,200']),
            SheetRow(<String>['Gate', '2', '1,400']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'الرصيف الشمالي' : 'North Dock',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'property.tenant-statement' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'إسكان الرصيف' : 'Dock Housing',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'سامي ناصر' : 'Sami Nasser'),
        labels: arabic
            ? SheetLabels(
              document: 'كشف مستأجر',
              from: 'المكتب',
              to: 'المستأجر',
              number: 'الوحدة',
              date: 'التاريخ',
              extra: 'الشهر',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'التاريخ',
                'البيان',
                'مطلوب',
                'مدفوع',
              ],
            )
            : SheetLabels(
              document: 'Tenant statement',
              from: 'Office',
              to: 'Tenant',
              number: 'Unit',
              date: 'Date',
              extra: 'Month',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Date',
                'Detail',
                'Charge',
                'Paid',
              ],
            ),
        number: '4B',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'أيلول' : 'September',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['01 أيلول', 'إيجار', '650', '650']),
            SheetRow(<String>['01 أيلول', 'ماء', '18', '18']),
          ] : const <SheetRow>[
            SheetRow(<String>['01 Sep', 'Rent', '650', '650']),
            SheetRow(<String>['01 Sep', 'Water', '18', '18']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'إسكان الرصيف' : 'Dock Housing',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'people.offer' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'الرصيف الشمالي' : 'North Dock',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'لينا حداد' : 'Lina Haddad'),
        labels: arabic
            ? SheetLabels(
              document: 'خطاب عرض',
              from: 'صاحب العمل',
              to: 'المرشّح',
              number: 'العرض',
              date: 'التاريخ',
              extra: 'البداية',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'البيان',
                'المبلغ',
              ],
            )
            : SheetLabels(
              document: 'Offer letter',
              from: 'Employer',
              to: 'Candidate',
              number: 'Offer',
              date: 'Date',
              extra: 'Start',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Detail',
                'Amount',
              ],
            ),
        number: 'OF-3',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? '01 تشرين الأول 2026' : '01 Oct 2026',
        subject: arabic ? 'قيادة العيادة' : 'Clinic lead',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[] : const <SheetRow>[],
        paragraphs: arabic ? const <String>[
            'منصب عيادة الليل لك إن قبلت قبل الجمعة.',
          ] : const <String>[
            'The night clinic post is yours if you accept by Friday.',
          ],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'الرصيف الشمالي' : 'North Dock',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'people.appointment' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'الرصيف الشمالي' : 'North Dock',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'لينا حداد' : 'Lina Haddad'),
        labels: arabic
            ? SheetLabels(
              document: 'خطاب تعيين',
              from: 'صاحب العمل',
              to: 'الموظف',
              number: 'الخطاب',
              date: 'التاريخ',
              extra: 'المنصب',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'البيان',
                'المبلغ',
              ],
            )
            : SheetLabels(
              document: 'Appointment letter',
              from: 'Employer',
              to: 'Employee',
              number: 'Letter',
              date: 'Date',
              extra: 'Post',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Detail',
                'Amount',
              ],
            ),
        number: 'AP-3',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'قيادة العيادة' : 'Clinic lead',
        subject: arabic ? 'التعيين' : 'Appointment',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[] : const <SheetRow>[],
        paragraphs: arabic ? const <String>[
            'تبدأ فجراً في 1 تشرين الأول. مفتاح البوابة عند سامي.',
          ] : const <String>[
            'You start at dawn on 1 October. The gate key is with Sami.',
          ],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'الرصيف الشمالي' : 'North Dock',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'people.experience' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'الرصيف الشمالي' : 'North Dock',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'إلى من يهمه الأمر' : 'To whom it may concern'),
        labels: arabic
            ? SheetLabels(
              document: 'شهادة خبرة',
              from: 'صاحب العمل',
              to: 'إلى من يهمه',
              number: 'الخطاب',
              date: 'التاريخ',
              extra: 'الخدمة',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'البيان',
                'المبلغ',
              ],
            )
            : SheetLabels(
              document: 'Experience letter',
              from: 'Employer',
              to: 'To whom',
              number: 'Letter',
              date: 'Date',
              extra: 'Served',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Detail',
                'Amount',
              ],
            ),
        number: 'EX-8',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? '2024–2026' : '2024–2026',
        subject: arabic ? 'الخدمة' : 'Service',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[] : const <SheetRow>[],
        paragraphs: arabic ? const <String>[
            'لينا حداد أدارت جدول عيادة الليل لسنتين.',
          ] : const <String>[
            'Lina Haddad kept the night clinic roster for two years.',
          ],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'الرصيف الشمالي' : 'North Dock',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'people.warning' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'الرصيف الشمالي' : 'North Dock',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'عمر ناصر' : 'Omar Nasser'),
        labels: arabic
            ? SheetLabels(
              document: 'إنذار',
              from: 'المدير',
              to: 'الموظف',
              number: 'الإشعار',
              date: 'التاريخ',
              extra: 'الدرجة',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'البيان',
                'المبلغ',
              ],
            )
            : SheetLabels(
              document: 'Warning notice',
              from: 'Manager',
              to: 'Employee',
              number: 'Notice',
              date: 'Date',
              extra: 'Level',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Detail',
                'Amount',
              ],
            ),
        number: 'WN-1',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'أول' : 'First',
        subject: arabic ? 'تأخّر البوابة' : 'Late gate',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[] : const <SheetRow>[],
        paragraphs: arabic ? const <String>[
            'البوابة الشرقية بقيت مفتوحة بعد نوبة الفجر. أغلقها قبل المغادرة.',
          ] : const <String>[
            'The east gate was left open after the dawn watch. Close it before leaving.',
          ],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'الرصيف الشمالي' : 'North Dock',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'people.recommendation' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'الرصيف الشمالي' : 'North Dock',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'مكتب التوظيف' : 'Hiring desk'),
        labels: arabic
            ? SheetLabels(
              document: 'توصية',
              from: 'الكاتب',
              to: 'القارئ',
              number: 'الخطاب',
              date: 'التاريخ',
              extra: 'بشأن',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'البيان',
                'المبلغ',
              ],
            )
            : SheetLabels(
              document: 'Recommendation',
              from: 'Writer',
              to: 'Reader',
              number: 'Letter',
              date: 'Date',
              extra: 'About',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Detail',
                'Amount',
              ],
            ),
        number: 'RC-2',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'لينا حداد' : 'Lina Haddad',
        subject: arabic ? 'توصية' : 'Recommendation',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[] : const <SheetRow>[],
        paragraphs: arabic ? const <String>[
            'لينا تُبقي الجناح هادئاً وعدّ الحقائب مكتملاً.',
          ] : const <String>[
            'Lina keeps a calm ward and a complete kit count.',
          ],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'الرصيف الشمالي' : 'North Dock',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'people.leave' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'سامي ناصر' : 'Sami Nasser',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'التشغيل' : 'Operations'),
        labels: arabic
            ? SheetLabels(
              document: 'طلب إجازة',
              from: 'الموظف',
              to: 'المدير',
              number: 'الطلب',
              date: 'التاريخ',
              extra: 'الأيام',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'البيان',
                'المبلغ',
              ],
            )
            : SheetLabels(
              document: 'Leave request',
              from: 'Employee',
              to: 'Manager',
              number: 'Request',
              date: 'Date',
              extra: 'Days',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Detail',
                'Amount',
              ],
            ),
        number: 'LV-6',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? '2' : '2',
        subject: arabic ? 'سفر عائلي' : 'Family travel',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[] : const <SheetRow>[],
        paragraphs: arabic ? const <String>[
            'أطلب 16 و17 أيلول. عمر يغطي بوابة الليل.',
          ] : const <String>[
            'I ask for 16 and 17 September. Omar covers the night gate.',
          ],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'سامي ناصر' : 'Sami Nasser',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'people.welcome' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'الرصيف الشمالي' : 'North Dock',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'لينا حداد' : 'Lina Haddad'),
        labels: arabic
            ? SheetLabels(
              document: 'رسالة ترحيب',
              from: 'المضيف',
              to: 'الوافد',
              number: 'الرسالة',
              date: 'التاريخ',
              extra: 'المكتب',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'البيان',
                'المبلغ',
              ],
            )
            : SheetLabels(
              document: 'Welcome note',
              from: 'Host',
              to: 'Newcomer',
              number: 'Note',
              date: 'Date',
              extra: 'Desk',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Detail',
                'Amount',
              ],
            ),
        number: 'WN-4',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'الجناح ب' : 'Ward B',
        subject: arabic ? 'أهلاً' : 'Welcome',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[] : const <SheetRow>[],
        paragraphs: arabic ? const <String>[
            'مفتاحك عند البوابة الشرقية. الجدول الأول على اللوح.',
          ] : const <String>[
            'Your key is at the east gate. The first roster is on the board.',
          ],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'الرصيف الشمالي' : 'North Dock',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'people.relieving' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'الرصيف الشمالي' : 'North Dock',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'عمر ناصر' : 'Omar Nasser'),
        labels: arabic
            ? SheetLabels(
              document: 'خطاب إخلاء طرف',
              from: 'صاحب العمل',
              to: 'الموظف',
              number: 'الخطاب',
              date: 'التاريخ',
              extra: 'آخر يوم',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'البيان',
                'المبلغ',
              ],
            )
            : SheetLabels(
              document: 'Relieving letter',
              from: 'Employer',
              to: 'Employee',
              number: 'Letter',
              date: 'Date',
              extra: 'Last day',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Detail',
                'Amount',
              ],
            ),
        number: 'RL-1',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? '30 أيلول 2026' : '30 Sep 2026',
        subject: arabic ? 'إخلاء طرف' : 'Relieving',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[] : const <SheetRow>[],
        paragraphs: arabic ? const <String>[
            'مفتاح البوابة واللاسلكي عادا إلى المستودع.',
          ] : const <String>[
            'The gate key and the radio are back in the store.',
          ],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'الرصيف الشمالي' : 'North Dock',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'people.reference' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'الرصيف الشمالي' : 'North Dock',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'إلى من يهمه الأمر' : 'To whom it may concern'),
        labels: arabic
            ? SheetLabels(
              document: 'خطاب تعريف',
              from: 'الجهة',
              to: 'القارئ',
              number: 'الخطاب',
              date: 'التاريخ',
              extra: 'بشأن',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'البيان',
                'المبلغ',
              ],
            )
            : SheetLabels(
              document: 'Reference letter',
              from: 'House',
              to: 'Reader',
              number: 'Letter',
              date: 'Date',
              extra: 'About',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Detail',
                'Amount',
              ],
            ),
        number: 'RF-5',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'سامي ناصر' : 'Sami Nasser',
        subject: arabic ? 'تعريف' : 'Reference',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[] : const <SheetRow>[],
        paragraphs: arabic ? const <String>[
            'سامي ناصر يعمل بوابة الليل ويحمل المفتاح GT-2.',
          ] : const <String>[
            'Sami Nasser works the night gate and holds key GT-2.',
          ],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'الرصيف الشمالي' : 'North Dock',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'education.admission' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'مدرسة النهر' : 'River School',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'عمر ناصر' : 'Omar Nasser'),
        labels: arabic
            ? SheetLabels(
              document: 'خطاب قبول',
              from: 'المدرسة',
              to: 'الطالب',
              number: 'العرض',
              date: 'التاريخ',
              extra: 'البداية',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'البيان',
                'المبلغ',
              ],
            )
            : SheetLabels(
              document: 'Admission letter',
              from: 'School',
              to: 'Student',
              number: 'Offer',
              date: 'Date',
              extra: 'Start',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Detail',
                'Amount',
              ],
            ),
        number: 'AD-7',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? '01 تشرين الأول 2026' : '01 Oct 2026',
        subject: arabic ? 'القبول' : 'Admission',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[] : const <SheetRow>[],
        paragraphs: arabic ? const <String>[
            'مقعد في الصف الثالث مفتوح إن أكّدت قبل الجمعة.',
          ] : const <String>[
            'A place in Form 3 is open if you confirm by Friday.',
          ],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'مدرسة النهر' : 'River School',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'narrative.announcement' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'التشغيل' : 'Operations',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'كل النوبات' : 'All watches'),
        labels: arabic
            ? SheetLabels(
              document: 'إعلان',
              from: 'من',
              to: 'الجمهور',
              number: 'الإعلان',
              date: 'التاريخ',
              extra: 'يسري',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'البيان',
                'المبلغ',
              ],
            )
            : SheetLabels(
              document: 'Announcement',
              from: 'From',
              to: 'Audience',
              number: 'Notice',
              date: 'Date',
              extra: 'Effective',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Detail',
                'Amount',
              ],
            ),
        number: 'AN-2',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? '15 أيلول 2026' : '15 Sep 2026',
        subject: arabic ? 'ساعات البوابة' : 'Gate hours',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[] : const <SheetRow>[],
        paragraphs: arabic ? const <String>[
            'البوابة الشرقية تُغلق عند 18:00 ابتداءً من الجمعة.',
          ] : const <String>[
            'The east gate closes at 18:00 from Friday.',
          ],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'التشغيل' : 'Operations',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'narrative.meeting-notice' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'التشغيل' : 'Operations',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'مسؤولو الأجنحة' : 'Ward leads'),
        labels: arabic
            ? SheetLabels(
              document: 'إشعار اجتماع',
              from: 'الداعي',
              to: 'المدعوون',
              number: 'الإشعار',
              date: 'التاريخ',
              extra: 'القاعة',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'البيان',
                'المبلغ',
              ],
            )
            : SheetLabels(
              document: 'Meeting notice',
              from: 'Caller',
              to: 'Invited',
              number: 'Notice',
              date: 'Date',
              extra: 'Room',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Detail',
                'Amount',
              ],
            ),
        number: 'MN-5',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'القاعة' : 'Hall',
        subject: arabic ? 'مراجعة الجمعة' : 'Friday review',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[] : const <SheetRow>[],
        paragraphs: arabic ? const <String>[
            'أحضر سجل المشكلات المفتوحة. ننتهي عند الظهر.',
          ] : const <String>[
            'Bring the open issue log. We stop at noon.',
          ],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'التشغيل' : 'Operations',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'narrative.decision' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'التشغيل' : 'Operations',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'فريق الرصيف' : 'Dock team'),
        labels: arabic
            ? SheetLabels(
              document: 'مذكرة قرار',
              from: 'صاحب القرار',
              to: 'الجمهور',
              number: 'القرار',
              date: 'التاريخ',
              extra: 'يسري',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'البيان',
                'المبلغ',
              ],
            )
            : SheetLabels(
              document: 'Decision note',
              from: 'Decider',
              to: 'Audience',
              number: 'Decision',
              date: 'Date',
              extra: 'Effective',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Detail',
                'Amount',
              ],
            ),
        number: 'DC-2',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? '15 أيلول 2026' : '15 Sep 2026',
        subject: arabic ? 'الإغلاق عند 18:00' : 'Close at 18:00',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[] : const <SheetRow>[],
        paragraphs: arabic ? const <String>[
            'البوابة الشرقية تُغلق عند 18:00. صناديق التبريد تخرج فجراً.',
          ] : const <String>[
            'The east gate closes at 18:00. Cold boxes still leave at dawn.',
          ],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'التشغيل' : 'Operations',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'people.internship' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'أكاديمية الميدان' : 'Field Academy',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'عيادة النهر' : 'River Clinic'),
        labels: arabic
            ? SheetLabels(
              document: 'شهادة تدريب',
              from: 'الجهة',
              to: 'إلى',
              number: 'الشهادة',
              date: 'التاريخ',
              extra: 'الساعات',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'البيان',
                'المبلغ',
              ],
            )
            : SheetLabels(
              document: 'Internship certificate',
              from: 'Issuer',
              to: 'To',
              number: 'Certificate',
              date: 'Date',
              extra: 'Hours',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Detail',
                'Amount',
              ],
            ),
        number: 'IC-12',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? '120' : '120',
        subject: arabic ? 'تناوب عيادة الليل' : 'Night clinic rotation',
        recipient: arabic ? 'عمر ناصر' : 'Omar Nasser',
        rows: arabic ? const <SheetRow>[] : const <SheetRow>[],
        paragraphs: arabic ? const <String>[
            'أتمّ اثنتي عشرة ليلة على جدول عيادة النهر.',
          ] : const <String>[
            'Completed twelve nights on the river clinic roster.',
          ],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'أكاديمية الميدان' : 'Field Academy',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المدير')]
            : const <SignSlot>[SignSlot(role: 'Director')],
      ).save(),
    'narrative.press' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'صندوق النهر' : 'River Fund',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'عيادة النهر' : 'River Clinic'),
        labels: arabic
            ? SheetLabels(
              document: 'بيان صحفي',
              from: 'من',
              to: 'إلى',
              number: 'البيان',
              date: 'التاريخ',
              extra: 'الحظر',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'البيان',
                'المبلغ',
              ],
            )
            : SheetLabels(
              document: 'Press release',
              from: 'From',
              to: 'To',
              number: 'Release',
              date: 'Date',
              extra: 'Embargo',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Detail',
                'Amount',
              ],
            ),
        number: 'PR-1',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'بلا' : 'None',
        subject: arabic ? 'افتتاح عيادة الليل' : 'Night clinic opens',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[] : const <SheetRow>[],
        paragraphs: arabic ? const <String>[
            'عيادة النهر تفتح مكتباً ليلياً من الأحد.',
          ] : const <String>[
            'The river clinic keeps a night desk from Sunday.',
          ],
        sections: arabic ? const <TemplateSection>[
            TemplateSection(heading: 'اقتباس', body: 'البوابة تبقى مضاءة. الحقائب تُعدّ.'),
          ] : const <TemplateSection>[
            TemplateSection(heading: 'Quote', body: 'The gate stays lit. The kits are counted.'),
          ],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'صندوق النهر' : 'River Fund',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'narrative.project-status' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'عيادة الليل' : 'Night clinic',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'عيادة النهر' : 'River Clinic'),
        labels: arabic
            ? SheetLabels(
              document: 'حالة مشروع',
              from: 'من',
              to: 'إلى',
              number: 'الحالة',
              date: 'التاريخ',
              extra: 'المرحلة',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'البيان',
                'المبلغ',
              ],
            )
            : SheetLabels(
              document: 'Project status',
              from: 'From',
              to: 'To',
              number: 'Status',
              date: 'Date',
              extra: 'Phase',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Detail',
                'Amount',
              ],
            ),
        number: 'PS-2',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'التجهيز' : 'Fit-out',
        subject: arabic ? 'أسبوع التجهيز' : 'Fit-out week',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[] : const <SheetRow>[],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[
            TemplateSection(heading: 'تم', body: 'الكهرباء وصلت.'),
            TemplateSection(heading: 'التالي', body: 'غرفة التبريد في 20 أيلول.'),
          ] : const <TemplateSection>[
            TemplateSection(heading: 'Done', body: 'Power is in.'),
            TemplateSection(heading: 'Next', body: 'Cold room by 20 Sep.'),
          ],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'عيادة الليل' : 'Night clinic',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'narrative.policy' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'التشغيل' : 'Operations',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'عيادة النهر' : 'River Clinic'),
        labels: arabic
            ? SheetLabels(
              document: 'ملاحظة سياسة',
              from: 'من',
              to: 'إلى',
              number: 'السياسة',
              date: 'التاريخ',
              extra: 'تلزم',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'البيان',
                'المبلغ',
              ],
            )
            : SheetLabels(
              document: 'Policy note',
              from: 'From',
              to: 'To',
              number: 'Policy',
              date: 'Date',
              extra: 'Binds',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Detail',
                'Amount',
              ],
            ),
        number: 'PN-4',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'كل النوبات' : 'All watches',
        subject: arabic ? 'ضبط المفاتيح' : 'Key control',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[] : const <SheetRow>[],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[
            TemplateSection(heading: 'القاعدة', body: 'المفاتيح تعود إلى اللوح في نهاية النوبة.'),
          ] : const <TemplateSection>[
            TemplateSection(heading: 'Rule', body: 'Keys return to the board at the end of the watch.'),
          ],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'التشغيل' : 'Operations',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'narrative.executive' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'التشغيل' : 'Operations',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'عيادة النهر' : 'River Clinic'),
        labels: arabic
            ? SheetLabels(
              document: 'ملخص تنفيذي',
              from: 'من',
              to: 'إلى',
              number: 'الإحاطة',
              date: 'التاريخ',
              extra: 'إلى',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'البيان',
                'المبلغ',
              ],
            )
            : SheetLabels(
              document: 'Executive summary',
              from: 'From',
              to: 'To',
              number: 'Brief',
              date: 'Date',
              extra: 'For',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Detail',
                'Amount',
              ],
            ),
        number: 'ES-1',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'مراجعة الجمعة' : 'Friday review',
        subject: arabic ? 'الأسبوع 37' : 'Week 37',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[] : const <SheetRow>[],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[
            TemplateSection(heading: 'الطلب', body: 'اعتمد موعد غرفة التبريد.'),
            TemplateSection(heading: 'المخاطرة', body: 'صندوق ما زال ناقصاً.'),
          ] : const <TemplateSection>[
            TemplateSection(heading: 'Ask', body: 'Approve the cold-room date.'),
            TemplateSection(heading: 'Risk', body: 'One crate is still short.'),
          ],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'التشغيل' : 'Operations',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'narrative.after-action' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'سلامة الرصيف' : 'Dock safety',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'عيادة النهر' : 'River Clinic'),
        labels: arabic
            ? SheetLabels(
              document: 'مراجعة ما بعد العمل',
              from: 'من',
              to: 'إلى',
              number: 'المراجعة',
              date: 'التاريخ',
              extra: 'الحدث',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'البيان',
                'المبلغ',
              ],
            )
            : SheetLabels(
              document: 'After-action review',
              from: 'From',
              to: 'To',
              number: 'Review',
              date: 'Date',
              extra: 'Event',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Detail',
                'Amount',
              ],
            ),
        number: 'AA-3',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'عاصفة الليل' : 'Night storm',
        subject: arabic ? 'عاصفة الليل' : 'Night storm',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[] : const <SheetRow>[],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[
            TemplateSection(heading: 'يُبقى', body: 'عدّ الفجر تمّ.'),
            TemplateSection(heading: 'يُغيّر', body: 'انقل المصابيح عن الجدار الشرقي.'),
          ] : const <TemplateSection>[
            TemplateSection(heading: 'Keep', body: 'The dawn count still ran.'),
            TemplateSection(heading: 'Change', body: 'Move lamps off the east wall.'),
          ],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'سلامة الرصيف' : 'Dock safety',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'narrative.newsletter' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'صندوق النهر' : 'River Fund',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'عيادة النهر' : 'River Clinic'),
        labels: arabic
            ? SheetLabels(
              document: 'نشرة',
              from: 'من',
              to: 'إلى',
              number: 'العدد',
              date: 'التاريخ',
              extra: 'الشهر',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'البيان',
                'المبلغ',
              ],
            )
            : SheetLabels(
              document: 'Newsletter',
              from: 'From',
              to: 'To',
              number: 'Issue',
              date: 'Date',
              extra: 'Month',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Detail',
                'Amount',
              ],
            ),
        number: 'NL-9',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'أيلول' : 'September',
        subject: arabic ? 'ملاحظات الميناء' : 'Harbour notes',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[] : const <SheetRow>[],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[
            TemplateSection(heading: 'العيادة', body: 'المكتب الليلي يفتح الأحد.'),
            TemplateSection(heading: 'المدرسة', body: 'الصف الثالث ما زال فيه مقعدان.'),
          ] : const <TemplateSection>[
            TemplateSection(heading: 'Clinic', body: 'Night desk opens Sunday.'),
            TemplateSection(heading: 'School', body: 'Form 3 still has two places.'),
          ],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'صندوق النهر' : 'River Fund',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'narrative.proposal' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'عيادة الليل' : 'Night clinic',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'عيادة النهر' : 'River Clinic'),
        labels: arabic
            ? SheetLabels(
              document: 'مقترح',
              from: 'من',
              to: 'إلى',
              number: 'المقترح',
              date: 'التاريخ',
              extra: 'الطلب',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'البيان',
                'المبلغ',
              ],
            )
            : SheetLabels(
              document: 'Proposal',
              from: 'From',
              to: 'To',
              number: 'Proposal',
              date: 'Date',
              extra: 'Ask',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Detail',
                'Amount',
              ],
            ),
        number: 'PP-2',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'غرفة تبريد' : 'Cold room',
        subject: arabic ? 'غرفة التبريد' : 'Cold room',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[] : const <SheetRow>[],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[
            TemplateSection(heading: 'العمل', body: 'تجهيز غرفة تبريد في 20 أيلول.'),
            TemplateSection(heading: 'الطلب', body: 'اعتمد عرض الشحن FQ-5.'),
          ] : const <TemplateSection>[
            TemplateSection(heading: 'Work', body: 'Fit a cold room by 20 Sep.'),
            TemplateSection(heading: 'Ask', body: 'Approve the freight quote FQ-5.'),
          ],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'عيادة الليل' : 'Night clinic',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'operations.safety' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'سلامة الرصيف' : 'Dock safety',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'عيادة النهر' : 'River Clinic'),
        labels: arabic
            ? SheetLabels(
              document: 'إحاطة سلامة',
              from: 'من',
              to: 'إلى',
              number: 'الإحاطة',
              date: 'التاريخ',
              extra: 'النوبة',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'البيان',
                'المبلغ',
              ],
            )
            : SheetLabels(
              document: 'Safety briefing',
              from: 'From',
              to: 'To',
              number: 'Brief',
              date: 'Date',
              extra: 'Watch',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Detail',
                'Amount',
              ],
            ),
        number: 'SB-14',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'الليل' : 'Night',
        subject: arabic ? 'رصيف مبلل' : 'Wet dock',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[] : const <SheetRow>[],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[
            TemplateSection(heading: 'الخطر', body: 'الساحة الشرقية مبللة.'),
            TemplateSection(heading: 'القاعدة', body: 'لا رافعة يدوية بعد المطر.'),
          ] : const <TemplateSection>[
            TemplateSection(heading: 'Hazard', body: 'The east apron is wet.'),
            TemplateSection(heading: 'Rule', body: 'No pallet jack after rain.'),
          ],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'سلامة الرصيف' : 'Dock safety',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'operations.incident' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'سلامة الرصيف' : 'Dock safety',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'عيادة النهر' : 'River Clinic'),
        labels: arabic
            ? SheetLabels(
              document: 'بلاغ حادث',
              from: 'من',
              to: 'إلى',
              number: 'البلاغ',
              date: 'التاريخ',
              extra: 'المكان',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'البيان',
                'المبلغ',
              ],
            )
            : SheetLabels(
              document: 'Incident report',
              from: 'From',
              to: 'To',
              number: 'Report',
              date: 'Date',
              extra: 'Place',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Detail',
                'Amount',
              ],
            ),
        number: 'IR-7',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'البوابة الشرقية' : 'East gate',
        subject: arabic ? 'بوابة مفتوحة' : 'Open gate',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[] : const <SheetRow>[],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[
            TemplateSection(heading: 'الواقعة', body: 'البوابة كانت مفتوحة عند 06:10.'),
            TemplateSection(heading: 'التغيير', body: 'المفاتيح تعود إلى اللوح.'),
          ] : const <TemplateSection>[
            TemplateSection(heading: 'Fact', body: 'The gate was open at 06:10.'),
            TemplateSection(heading: 'Change', body: 'Keys return to the board.'),
          ],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'سلامة الرصيف' : 'Dock safety',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'operations.handover' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'نوبة الفجر' : 'Dawn watch',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'نوبة النهار' : 'Day watch'),
        labels: arabic
            ? SheetLabels(
              document: 'محضر تسليم',
              from: 'من نوبة',
              to: 'إلى نوبة',
              number: 'التسليم',
              date: 'التاريخ',
              extra: 'بنود مفتوحة',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'البيان',
                'المبلغ',
              ],
            )
            : SheetLabels(
              document: 'Handover',
              from: 'From watch',
              to: 'To watch',
              number: 'Handover',
              date: 'Date',
              extra: 'Open items',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Detail',
                'Amount',
              ],
            ),
        number: 'HO-14',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? '2' : '2',
        subject: arabic ? 'من الفجر إلى النهار' : 'Dawn to day',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[] : const <SheetRow>[],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[
            TemplateSection(heading: 'مفتوح', body: 'الإنارة الشرقية ما زالت مطفأة.'),
            TemplateSection(heading: 'المفاتيح', body: 'GT-2 عند سامي.'),
          ] : const <TemplateSection>[
            TemplateSection(heading: 'Open', body: 'East light is still out.'),
            TemplateSection(heading: 'Keys', body: 'GT-2 is with Sami.'),
          ],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'نوبة الفجر' : 'Dawn watch',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'operations.change' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'الورشة' : 'Workshop',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'عيادة النهر' : 'River Clinic'),
        labels: arabic
            ? SheetLabels(
              document: 'طلب تغيير',
              from: 'من',
              to: 'إلى',
              number: 'الطلب',
              date: 'التاريخ',
              extra: 'النافذة',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'البيان',
                'المبلغ',
              ],
            )
            : SheetLabels(
              document: 'Change request',
              from: 'From',
              to: 'To',
              number: 'Request',
              date: 'Date',
              extra: 'Window',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Detail',
                'Amount',
              ],
            ),
        number: 'CR-4',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'فجر الجمعة' : 'Friday dawn',
        subject: arabic ? 'نقل المصباح' : 'Move the lamp',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[] : const <SheetRow>[],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[
            TemplateSection(heading: 'التغيير', body: 'انقل مصباح الشرق عن الجدار المبلل.'),
            TemplateSection(heading: 'السبب', body: 'العاصفة الأخيرة قصرته.'),
          ] : const <TemplateSection>[
            TemplateSection(heading: 'Change', body: 'Move the east lamp off the wet wall.'),
            TemplateSection(heading: 'Why', body: 'Last storm shorted it.'),
          ],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'الورشة' : 'Workshop',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'education.syllabus' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'مدرسة النهر' : 'River School',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'عيادة النهر' : 'River Clinic'),
        labels: arabic
            ? SheetLabels(
              document: 'منهج',
              from: 'من',
              to: 'إلى',
              number: 'المساق',
              date: 'التاريخ',
              extra: 'الفصل',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'البيان',
                'المبلغ',
              ],
            )
            : SheetLabels(
              document: 'Syllabus',
              from: 'From',
              to: 'To',
              number: 'Course',
              date: 'Date',
              extra: 'Term',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Detail',
                'Amount',
              ],
            ),
        number: 'SY-3',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'الخريف' : 'Autumn',
        subject: arabic ? 'علوم، الصف الثالث' : 'Science, Form 3',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[] : const <SheetRow>[],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[
            TemplateSection(heading: 'الأسبوع 1', body: 'الماء وسلسلة التبريد.'),
            TemplateSection(heading: 'الأسبوع 2', body: 'عدّ حقيبة.'),
          ] : const <TemplateSection>[
            TemplateSection(heading: 'Week 1', body: 'Water and the cold chain.'),
            TemplateSection(heading: 'Week 2', body: 'Counting a kit.'),
          ],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'مدرسة النهر' : 'River School',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'education.assignment' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'مدرسة النهر' : 'River School',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'عيادة النهر' : 'River Clinic'),
        labels: arabic
            ? SheetLabels(
              document: 'موجز واجب',
              from: 'من',
              to: 'إلى',
              number: 'الواجب',
              date: 'التاريخ',
              extra: 'الاستحقاق',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'البيان',
                'المبلغ',
              ],
            )
            : SheetLabels(
              document: 'Assignment brief',
              from: 'From',
              to: 'To',
              number: 'Task',
              date: 'Date',
              extra: 'Due',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Detail',
                'Amount',
              ],
            ),
        number: 'AS-2',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? '21 أيلول 2026' : '21 Sep 2026',
        subject: arabic ? 'عدّ حقيبة' : 'Count a kit',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[] : const <SheetRow>[],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[
            TemplateSection(heading: 'المهمة', body: 'اذكر ما نقص من حقيبة ميدانية.'),
            TemplateSection(heading: 'الجيد', body: 'اثنا عشر سطراً وملاحظة صورة.'),
          ] : const <TemplateSection>[
            TemplateSection(heading: 'Task', body: 'List what is missing from a field kit.'),
            TemplateSection(heading: 'Good', body: 'Twelve lines, one photo note.'),
          ],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'مدرسة النهر' : 'River School',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'education.progress' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'مدرسة النهر' : 'River School',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'لينا حداد' : 'Lina Haddad'),
        labels: arabic
            ? SheetLabels(
              document: 'تقرير تقدم',
              from: 'المدرسة',
              to: 'الطالب',
              number: 'التقرير',
              date: 'التاريخ',
              extra: 'الفصل',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'البيان',
                'المبلغ',
              ],
            )
            : SheetLabels(
              document: 'Progress report',
              from: 'School',
              to: 'Student',
              number: 'Report',
              date: 'Date',
              extra: 'Term',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Detail',
                'Amount',
              ],
            ),
        number: 'PG-3',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'الخريف' : 'Autumn',
        subject: arabic ? 'ملاحظة الخريف' : 'Autumn note',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[] : const <SheetRow>[],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[
            TemplateSection(heading: 'القوة', body: 'العربية واضحة.'),
            TemplateSection(heading: 'التالي', body: 'تطبيقات العلوم.'),
          ] : const <TemplateSection>[
            TemplateSection(heading: 'Strength', body: 'Arabic is clear.'),
            TemplateSection(heading: 'Next', body: 'Science practicals.'),
          ],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'مدرسة النهر' : 'River School',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'property.lease' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'إسكان الرصيف' : 'Dock Housing',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'سامي ناصر' : 'Sami Nasser'),
        labels: arabic
            ? SheetLabels(
              document: 'ملخص عقد',
              from: 'المكتب',
              to: 'المستأجر',
              number: 'الوحدة',
              date: 'التاريخ',
              extra: 'المدة',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'البيان',
                'المبلغ',
              ],
            )
            : SheetLabels(
              document: 'Lease summary',
              from: 'Office',
              to: 'Tenant',
              number: 'Unit',
              date: 'Date',
              extra: 'Term',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Detail',
                'Amount',
              ],
            ),
        number: '4B',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? '12 شهراً' : '12 months',
        subject: arabic ? 'الوحدة 4B' : 'Unit 4B',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[] : const <SheetRow>[],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[
            TemplateSection(heading: 'الإيجار', body: '650 كل شهر، في الأول.'),
            TemplateSection(heading: 'المفاتيح', body: 'طقم واحد يُعاد في اليوم الأخير.'),
          ] : const <TemplateSection>[
            TemplateSection(heading: 'Rent', body: '650 each month, due on the first.'),
            TemplateSection(heading: 'Keys', body: 'One set, returned on the last day.'),
          ],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'إسكان الرصيف' : 'Dock Housing',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'programs.grant' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'صندوق النهر' : 'River Fund',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'عيادة النهر' : 'River Clinic'),
        labels: arabic
            ? SheetLabels(
              document: 'تقرير منحة',
              from: 'من',
              to: 'إلى',
              number: 'المنحة',
              date: 'التاريخ',
              extra: 'الفترة',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'البيان',
                'المبلغ',
              ],
            )
            : SheetLabels(
              document: 'Grant report',
              from: 'From',
              to: 'To',
              number: 'Grant',
              date: 'Date',
              extra: 'Period',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Detail',
                'Amount',
              ],
            ),
        number: 'GR-2',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'الربع الثالث' : 'Q3',
        subject: arabic ? 'حقائب العيادة' : 'Clinic kits',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[] : const <SheetRow>[],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[
            TemplateSection(heading: 'صُرف', body: 'اثنتا عشرة حقيبة وأربعة صناديق تبريد.'),
            TemplateSection(heading: 'تبقّى', body: 'تجهيز غرفة التبريد.'),
          ] : const <TemplateSection>[
            TemplateSection(heading: 'Spent', body: 'Twelve kits and four cold boxes.'),
            TemplateSection(heading: 'Left', body: 'The cold-room fit-out.'),
          ],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'صندوق النهر' : 'River Fund',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'programs.brief' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'صندوق النهر' : 'River Fund',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'عيادة النهر' : 'River Clinic'),
        labels: arabic
            ? SheetLabels(
              document: 'إحاطة برنامج',
              from: 'من',
              to: 'إلى',
              number: 'الإحاطة',
              date: 'التاريخ',
              extra: 'الأسبوع',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'البيان',
                'المبلغ',
              ],
            )
            : SheetLabels(
              document: 'Program brief',
              from: 'From',
              to: 'To',
              number: 'Brief',
              date: 'Date',
              extra: 'Week',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Detail',
                'Amount',
              ],
            ),
        number: 'PB-37',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'الأسبوع 37' : 'Week 37',
        subject: arabic ? 'الجناح ب' : 'Ward B',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[] : const <SheetRow>[],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[
            TemplateSection(heading: 'خُدم', body: 'أسرتان استلمتا حقائب.'),
            TemplateSection(heading: 'التالي', body: 'الجولة 3 يوم الجمعة.'),
          ] : const <TemplateSection>[
            TemplateSection(heading: 'Served', body: 'Two households received kits.'),
            TemplateSection(heading: 'Next', body: 'Round 3 on Friday.'),
          ],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'صندوق النهر' : 'River Fund',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'operations.permit' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'سلامة الرصيف' : 'Dock safety',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'عيادة النهر' : 'River Clinic'),
        labels: arabic
            ? SheetLabels(
              document: 'تصريح عمل',
              from: 'من',
              to: 'إلى',
              number: 'التصريح',
              date: 'التاريخ',
              extra: 'العمل',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'العلامة',
                'ملاحظة',
              ],
            )
            : SheetLabels(
              document: 'Work permit',
              from: 'From',
              to: 'To',
              number: 'Permit',
              date: 'Date',
              extra: 'Job',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Mark',
                'Note',
              ],
            ),
        number: 'WP-6',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'مصباح الشرق' : 'East lamp',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['الكهرباء معزولة', 'نجاح', '']),
            SheetRow(<String>['مراقب حاضر', 'مفتوح', 'نحتاج واحداً']),
          ] : const <SheetRow>[
            SheetRow(<String>['Power isolated', 'Pass', '']),
            SheetRow(<String>['Spotter present', 'Open', 'Need one']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'سلامة الرصيف' : 'Dock safety',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'operations.audit' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'سلامة الرصيف' : 'Dock safety',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'عيادة النهر' : 'River Clinic'),
        labels: arabic
            ? SheetLabels(
              document: 'ملاحظات تدقيق',
              from: 'من',
              to: 'إلى',
              number: 'التدقيق',
              date: 'التاريخ',
              extra: 'الموقع',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'العلامة',
                'ملاحظة',
              ],
            )
            : SheetLabels(
              document: 'Audit findings',
              from: 'From',
              to: 'To',
              number: 'Audit',
              date: 'Date',
              extra: 'Site',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Mark',
                'Note',
              ],
            ),
        number: 'AU-2',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'مستودع 4' : 'Warehouse 4',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['لوح المفاتيح', 'فشل', 'GT-2 ناقص']),
            SheetRow(<String>['سلسلة التبريد', 'نجاح', '']),
          ] : const <SheetRow>[
            SheetRow(<String>['Key board', 'Fail', 'GT-2 missing']),
            SheetRow(<String>['Cold chain', 'Pass', '']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'سلامة الرصيف' : 'Dock safety',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'property.move-in' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'إسكان الرصيف' : 'Dock Housing',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'عيادة النهر' : 'River Clinic'),
        labels: arabic
            ? SheetLabels(
              document: 'قائمة استلام وحدة',
              from: 'من',
              to: 'إلى',
              number: 'الوحدة',
              date: 'التاريخ',
              extra: 'المستأجر',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'العلامة',
                'ملاحظة',
              ],
            )
            : SheetLabels(
              document: 'Move-in checklist',
              from: 'From',
              to: 'To',
              number: 'Unit',
              date: 'Date',
              extra: 'Tenant',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Mark',
                'Note',
              ],
            ),
        number: '4B',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'سامي ناصر' : 'Sami Nasser',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['المفاتيح', 'تم', 'طقم']),
            SheetRow(<String>['الإنارة', 'مفتوح', 'الغرفة الشرقية']),
          ] : const <SheetRow>[
            SheetRow(<String>['Keys', 'Done', 'One set']),
            SheetRow(<String>['Lights', 'Open', 'East room']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'إسكان الرصيف' : 'Dock Housing',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'property.maintenance' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'إسكان الرصيف' : 'Dock Housing',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'عيادة النهر' : 'River Clinic'),
        labels: arabic
            ? SheetLabels(
              document: 'طلب صيانة',
              from: 'من',
              to: 'إلى',
              number: 'الطلب',
              date: 'التاريخ',
              extra: 'الوحدة',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'العلامة',
                'ملاحظة',
              ],
            )
            : SheetLabels(
              document: 'Maintenance request',
              from: 'From',
              to: 'To',
              number: 'Request',
              date: 'Date',
              extra: 'Unit',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Mark',
                'Note',
              ],
            ),
        number: 'MR-8',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? '4B' : '4B',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[
            SheetRow(<String>['إنارة شرقية', 'مفتوح', 'لا مصباح']),
            SheetRow(<String>['حنفيّة', 'تم', 'جلدة']),
          ] : const <SheetRow>[
            SheetRow(<String>['East light', 'Open', 'No lamp']),
            SheetRow(<String>['Tap', 'Done', 'Washer']),
          ],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[] : const <(String, String)>[],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'إسكان الرصيف' : 'Dock Housing',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'data.scorecard' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'عيادة النهر' : 'River Clinic',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'عيادة النهر' : 'River Clinic'),
        labels: arabic
            ? SheetLabels(
              document: 'بطاقة أداء',
              from: 'من',
              to: 'إلى',
              number: 'البطاقة',
              date: 'التاريخ',
              extra: 'الفترة',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'البيان',
                'المبلغ',
              ],
            )
            : SheetLabels(
              document: 'Scorecard',
              from: 'From',
              to: 'To',
              number: 'Card',
              date: 'Date',
              extra: 'Period',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Detail',
                'Amount',
              ],
            ),
        number: 'SC-3',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'الربع الثالث' : 'Q3',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[] : const <SheetRow>[],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[
            ('الزيارات', '1,240'),
            ('في الموعد', '98%'),
            ('مفتوح', '4'),
          ] : const <(String, String)>[
            ('Visits', '1,240'),
            ('On time', '98%'),
            ('Open', '4'),
          ],
        chart: arabic ? const <ChartPoint>[
          ChartPoint(label: 'تموز', value: 380, color: '217346'),
          ChartPoint(label: 'آب', value: 410, color: '217346'),
          ChartPoint(label: 'أيلول', value: 450, color: '217346'),
        ] : const <ChartPoint>[
          ChartPoint(label: 'Jul', value: 380, color: '217346'),
          ChartPoint(label: 'Aug', value: 410, color: '217346'),
          ChartPoint(label: 'Sep', value: 450, color: '217346'),
        ],
        chartTitle: arabic ? 'الزيارات' : 'Visits',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'عيادة النهر' : 'River Clinic',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'data.survey' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'صندوق النهر' : 'River Fund',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'عيادة النهر' : 'River Clinic'),
        labels: arabic
            ? SheetLabels(
              document: 'نتائج استبيان',
              from: 'من',
              to: 'إلى',
              number: 'الاستبيان',
              date: 'التاريخ',
              extra: 'العدد',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'البيان',
                'المبلغ',
              ],
            )
            : SheetLabels(
              document: 'Survey results',
              from: 'From',
              to: 'To',
              number: 'Survey',
              date: 'Date',
              extra: 'n',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Detail',
                'Amount',
              ],
            ),
        number: 'SV-1',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? '42' : '42',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[] : const <SheetRow>[],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[
            ('واضح', '31'),
            ('غير واضح', '8'),
            ('بلا جواب', '3'),
          ] : const <(String, String)>[
            ('Clear', '31'),
            ('Unclear', '8'),
            ('No answer', '3'),
          ],
        chart: arabic ? const <ChartPoint>[
          ChartPoint(label: 'واضح', value: 31, color: '217346'),
          ChartPoint(label: 'غير واضح', value: 8, color: '217346'),
          ChartPoint(label: 'بلا', value: 3, color: '217346'),
        ] : const <ChartPoint>[
          ChartPoint(label: 'Clear', value: 31, color: '217346'),
          ChartPoint(label: 'Unclear', value: 8, color: '217346'),
          ChartPoint(label: 'None', value: 3, color: '217346'),
        ],
        chartTitle: arabic ? 'الإجابات' : 'Answers',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'صندوق النهر' : 'River Fund',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'data.capacity' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'التشغيل' : 'Operations',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'عيادة النهر' : 'River Clinic'),
        labels: arabic
            ? SheetLabels(
              document: 'تقرير طاقة',
              from: 'من',
              to: 'إلى',
              number: 'التقرير',
              date: 'التاريخ',
              extra: 'اليوم',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'البيان',
                'المبلغ',
              ],
            )
            : SheetLabels(
              document: 'Capacity report',
              from: 'From',
              to: 'To',
              number: 'Report',
              date: 'Date',
              extra: 'Day',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Detail',
                'Amount',
              ],
            ),
        number: 'CAP-14',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? '14 أيلول' : '14 Sep',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[] : const <SheetRow>[],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[
            ('أسرّة', '18 / 20'),
            ('المخزن', '70%'),
            ('فانات', 'واحد فارغ'),
          ] : const <(String, String)>[
            ('Beds', '18 / 20'),
            ('Store', '70%'),
            ('Vans', '1 free'),
          ],
        chart: arabic ? const <ChartPoint>[
          ChartPoint(label: 'الإثنين', value: 14, color: '217346'),
          ChartPoint(label: 'الثلاثاء', value: 16, color: '217346'),
          ChartPoint(label: 'الأربعاء', value: 18, color: '217346'),
        ] : const <ChartPoint>[
          ChartPoint(label: 'Mon', value: 14, color: '217346'),
          ChartPoint(label: 'Tue', value: 16, color: '217346'),
          ChartPoint(label: 'Wed', value: 18, color: '217346'),
        ],
        chartTitle: arabic ? 'أسرّة مستخدمة' : 'Beds used',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'التشغيل' : 'Operations',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'programs.impact' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'صندوق النهر' : 'River Fund',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'عيادة النهر' : 'River Clinic'),
        labels: arabic
            ? SheetLabels(
              document: 'ورقة أثر',
              from: 'من',
              to: 'إلى',
              number: 'الورقة',
              date: 'التاريخ',
              extra: 'الفترة',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'البيان',
                'المبلغ',
              ],
            )
            : SheetLabels(
              document: 'Impact sheet',
              from: 'From',
              to: 'To',
              number: 'Sheet',
              date: 'Date',
              extra: 'Period',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Detail',
                'Amount',
              ],
            ),
        number: 'IM-3',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'الربع الثالث' : 'Q3',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[] : const <SheetRow>[],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[
            ('أسر', '86'),
            ('حقائب', '120'),
            ('ليالٍ', '40'),
          ] : const <(String, String)>[
            ('Households', '86'),
            ('Kits', '120'),
            ('Nights', '40'),
          ],
        chart: arabic ? const <ChartPoint>[
          ChartPoint(label: 'تموز', value: 30, color: '9F1239'),
          ChartPoint(label: 'آب', value: 40, color: '9F1239'),
          ChartPoint(label: 'أيلول', value: 50, color: '9F1239'),
        ] : const <ChartPoint>[
          ChartPoint(label: 'Jul', value: 30, color: '9F1239'),
          ChartPoint(label: 'Aug', value: 40, color: '9F1239'),
          ChartPoint(label: 'Sep', value: 50, color: '9F1239'),
        ],
        chartTitle: arabic ? 'الحقائب' : 'Kits',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'صندوق النهر' : 'River Fund',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'operations.daily-site' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'مستودع 4' : 'Warehouse 4',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'عيادة النهر' : 'River Clinic'),
        labels: arabic
            ? SheetLabels(
              document: 'تقرير موقع يومي',
              from: 'من',
              to: 'إلى',
              number: 'اليوم',
              date: 'التاريخ',
              extra: 'الوردية',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'البيان',
                'المبلغ',
              ],
            )
            : SheetLabels(
              document: 'Daily site report',
              from: 'From',
              to: 'To',
              number: 'Day',
              date: 'Date',
              extra: 'Shift',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Detail',
                'Amount',
              ],
            ),
        number: 'DS-14',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'الفجر' : 'Dawn',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[] : const <SheetRow>[],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[
            ('داخل', '16'),
            ('خارج', '12'),
            ('مشكلات مفتوحة', '2'),
          ] : const <(String, String)>[
            ('In', '16'),
            ('Out', '12'),
            ('Open issues', '2'),
          ],
        chart: arabic ? const <ChartPoint>[
          ChartPoint(label: 'داخل', value: 16, color: '334155'),
          ChartPoint(label: 'خارج', value: 12, color: '334155'),
        ] : const <ChartPoint>[
          ChartPoint(label: 'In', value: 16, color: '334155'),
          ChartPoint(label: 'Out', value: 12, color: '334155'),
        ],
        chartTitle: arabic ? 'صناديق' : 'Crates',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'مستودع 4' : 'Warehouse 4',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'people.profile' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'لينا حداد' : 'Lina Haddad',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'عيادة النهر' : 'River Clinic'),
        labels: arabic
            ? SheetLabels(
              document: 'بطاقة موظف',
              from: 'من',
              to: 'إلى',
              number: 'الملف',
              date: 'التاريخ',
              extra: 'المنصب',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'البيان',
                'المبلغ',
              ],
            )
            : SheetLabels(
              document: 'Employee profile',
              from: 'From',
              to: 'To',
              number: 'File',
              date: 'Date',
              extra: 'Post',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Detail',
                'Amount',
              ],
            ),
        number: 'EMP-19',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'قيادة العيادة' : 'Clinic lead',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[] : const <SheetRow>[],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[
            ('سنوات', '2'),
            ('النوبة', 'فجر'),
            ('المفتاح', 'العيادة'),
          ] : const <(String, String)>[
            ('Years', '2'),
            ('Watches', 'Dawn'),
            ('Key', 'Clinic'),
          ],
        chart: arabic ? null : null,
        chartTitle: arabic ? '' : '',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'لينا حداد' : 'Lina Haddad',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
    'operations.maintenance' => ctor(
        direction: arabic ? TextDirection.rtl : TextDirection.ltr,
        font: font,
        fontBold: fontBold,
        from: TemplateParty(
          name: arabic ? 'الورشة' : 'Workshop',
          lines: <String>[
            arabic
                ? 'طريق الميناء'
                : 'Port Road',
          ],
        ),
        to: TemplateParty(name: arabic ? 'عيادة النهر' : 'River Clinic'),
        labels: arabic
            ? SheetLabels(
              document: 'سجل صيانة',
              from: 'من',
              to: 'إلى',
              number: 'السجل',
              date: 'التاريخ',
              extra: 'الأسبوع',
              subject: 'الموضوع',
              notes: 'ملاحظات',
              subtotal: 'المجموع',
              tax: 'الضريبة',
              total: 'الإجمالي',
              presentedTo: 'تُمنح إلى',
              columns: const <String>[
                'البند',
                'البيان',
                'المبلغ',
              ],
            )
            : SheetLabels(
              document: 'Maintenance log',
              from: 'From',
              to: 'To',
              number: 'Log',
              date: 'Date',
              extra: 'Week',
              subject: 'Subject',
              notes: 'Notes',
              subtotal: 'Subtotal',
              tax: 'Tax',
              total: 'Total',
              presentedTo: 'Presented to',
              columns: const <String>[
                'Item',
                'Detail',
                'Amount',
              ],
            ),
        number: 'ML-37',
        date: arabic ? '14 أيلول 2026' : '14 Sep 2026',
        extra: arabic ? 'الأسبوع 37' : 'Week 37',
        subject: arabic ? '' : '',
        recipient: arabic ? '' : '',
        rows: arabic ? const <SheetRow>[] : const <SheetRow>[],
        paragraphs: arabic ? const <String>[] : const <String>[],
        sections: arabic ? const <TemplateSection>[] : const <TemplateSection>[],
        metrics: arabic ? const <(String, String)>[
            ('أعمال', '5'),
            ('مفتوح', '1'),
            ('ساعات', '11'),
          ] : const <(String, String)>[
            ('Jobs', '5'),
            ('Open', '1'),
            ('Hours', '11'),
          ],
        chart: arabic ? const <ChartPoint>[
          ChartPoint(label: 'البوابة', value: 3, color: '334155'),
          ChartPoint(label: 'المصباح', value: 2, color: '334155'),
          ChartPoint(label: 'الحنفيّة', value: 1, color: '334155'),
        ] : const <ChartPoint>[
          ChartPoint(label: 'Gate', value: 3, color: '334155'),
          ChartPoint(label: 'Lamp', value: 2, color: '334155'),
          ChartPoint(label: 'Tap', value: 1, color: '334155'),
        ],
        chartTitle: arabic ? 'الساعات' : 'Hours',
        totals: null,
        notes: arabic ? 'استبدل كل عنوان. المبالغ نصوص منسّقة مسبقاً.' : 'Replace every label. Amounts stay formatted strings.',
        footer: arabic ? 'الورشة' : 'Workshop',
        signs: arabic
            ? const <SignSlot>[SignSlot(role: 'المسؤول')]
            : const <SignSlot>[SignSlot(role: 'Lead')],
      ).save(),
      _ => throw ArgumentError('Unknown suite template: $id'),
    };
  }
}
