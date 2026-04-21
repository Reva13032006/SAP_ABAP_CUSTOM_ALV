*&---------------------------------------------------------------------*
*& Program     : ZSD_SO_BACKLOG
*& Description : Sales Order Backlog & Delivery Monitor
*& Author      : Reva Sahu | Roll No. 23053292 | B.Tech 2023-2027
*& Module      : SAP SD - Sales & Distribution
*& Created     : April 2026
*&---------------------------------------------------------------------*
*& This program provides a single, live, colour-coded, drill-down
*& enabled ALV report for monitoring open Sales Order backlogs.
*& It reads VBAK/VBAP/VBEP/KNA1, classifies delivery delay status,
*& and presents results via CL_GUI_ALV_GRID in a docking container.
*&---------------------------------------------------------------------*

REPORT zsd_so_backlog LINE-SIZE 255 MESSAGE-ID zsd_msg.

*&---------------------------------------------------------------------*
*& INCLUDE: ZSDSO_TOP — Global Types, Data, Constants
*&---------------------------------------------------------------------*

TYPES: BEGIN OF ty_so_backlog,
  vbeln    TYPE vbeln_va,    " Sales Order Number
  posnr    TYPE posnr_va,    " Sales Order Item
  kunnr    TYPE kunnr,       " Sold-To Customer
  name1    TYPE name1_gp,    " Customer Name
  vkorg    TYPE vkorg,       " Sales Organisation
  matnr    TYPE matnr,       " Material Number
  arktx    TYPE arktx,       " Item Description
  kwmeng   TYPE kwmeng,      " Ordered Quantity
  lfimg    TYPE lfimg,       " Already Delivered Qty
  offen    TYPE kwmeng,      " Open (Pending) Quantity
  netpr    TYPE netpr,       " Net Price per Unit
  open_val TYPE wertv8,      " Open Order Value
  waerk    TYPE waerk,       " Sales Document Currency
  edatu    TYPE edatu,       " Confirmed Schedule Line Date
  audat    TYPE audat,       " Sales Order Creation Date
  delay_d  TYPE i,           " Delay in Days (negative = future)
  status   TYPE char12,      " Status Label
  icon_fld TYPE icon_d,      " Traffic-Light Icon
  row_col  TYPE char4,       " ALV Row Colour Code
END OF ty_so_backlog.

DATA: gt_items     TYPE STANDARD TABLE OF ty_so_backlog,
      gt_fieldcat  TYPE slis_t_fieldcat_alv,
      gs_layout    TYPE slis_layout_alv,
      go_container TYPE REF TO cl_gui_docking_container,
      go_grid      TYPE REF TO cl_gui_alv_grid.

CONSTANTS: lc_neg TYPE i VALUE -999999.  " Lower bound for on-schedule check

*&---------------------------------------------------------------------*
*& INCLUDE: ZSDSO_SEL — Selection Screen
*&---------------------------------------------------------------------*

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-001.
SELECT-OPTIONS:
  s_vkorg FOR vbak-vkorg OBLIGATORY,  " Sales Organisation (mandatory)
  s_kunnr FOR kna1-kunnr,              " Customer Number
  s_matnr FOR vbap-matnr,              " Material Number
  s_audat FOR vbak-audat,              " Order Creation Date
  s_vdatu FOR vbak-vdatu.              " Requested Delivery Date
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE TEXT-002.
PARAMETERS:
  p_open RADIOBUTTON GROUP r1 DEFAULT 'X',  " Open Orders Only
  p_all  RADIOBUTTON GROUP r1.               " All Sales Orders
SELECTION-SCREEN END OF BLOCK b2.

*&---------------------------------------------------------------------*
*& INCLUDE: ZSDSO_PAI — AT SELECTION-SCREEN Events
*&---------------------------------------------------------------------*

AT SELECTION-SCREEN ON VALUE-REQUEST FOR s_kunnr-low.
  CALL FUNCTION 'F4_KUNNR'
    EXPORTING vkorg = s_vkorg-low
    IMPORTING kunnr = s_kunnr-low.

AT SELECTION-SCREEN.
  AUTHORITY-CHECK OBJECT 'V_VBAK_VKO'
    ID 'VKORG' FIELD s_vkorg-low
    ID 'ACTVT' FIELD '03'.
  IF sy-subrc <> 0.
    MESSAGE e003 WITH s_vkorg-low.
  ENDIF.

*&---------------------------------------------------------------------*
*& INCLUDE: ZSDSO_CLS — Local Class Definitions & Implementations
*&---------------------------------------------------------------------*

*----------------------------------------------------------------------*
* CLASS: LCL_EVENT_HANDLER — forward declaration
*----------------------------------------------------------------------*
CLASS lcl_event_handler DEFINITION DEFERRED.

*----------------------------------------------------------------------*
* CLASS: LCL_SO_BACKLOG — Main business logic
*----------------------------------------------------------------------*
CLASS lcl_so_backlog DEFINITION.
  PUBLIC SECTION.
    METHODS:
      get_open_orders,
      compute_delay,
      build_fieldcat,
      set_layout,
      display_grid.
  PRIVATE SECTION.
    DATA: mt_items     TYPE STANDARD TABLE OF ty_so_backlog,
          mo_container TYPE REF TO cl_gui_docking_container,
          mo_grid      TYPE REF TO cl_gui_alv_grid.
ENDCLASS.

*----------------------------------------------------------------------*
* CLASS: LCL_EVENT_HANDLER — ALV event handler (double-click, toolbar)
*----------------------------------------------------------------------*
CLASS lcl_event_handler DEFINITION.
  PUBLIC SECTION.
    METHODS:
      on_double_click
        FOR EVENT double_click OF cl_gui_alv_grid
        IMPORTING e_row e_column,
      on_toolbar_click
        FOR EVENT toolbar OF cl_gui_alv_grid
        IMPORTING e_object e_interactive.
ENDCLASS.

*----------------------------------------------------------------------*
* CLASS: LCL_SO_BACKLOG IMPLEMENTATION
*----------------------------------------------------------------------*
CLASS lcl_so_backlog IMPLEMENTATION.

  "--------------------------------------------------------------------
  " METHOD: GET_OPEN_ORDERS
  " Reads open sales order lines from VBAK/VBAP/VBEP/KNA1
  "--------------------------------------------------------------------
  METHOD get_open_orders.
    DATA lt_raw TYPE STANDARD TABLE OF ty_so_backlog.

    SELECT k~vbeln p~posnr k~kunnr c~name1 k~vkorg
           p~matnr p~arktx p~kwmeng p~netpr k~waerk
           e~edatu k~audat
      FROM vbak AS k
      INNER JOIN vbap AS p ON p~vbeln = k~vbeln
      INNER JOIN vbep AS e ON e~vbeln = p~vbeln
                           AND e~posnr = p~posnr
                           AND e~etenr = '0001'        " First schedule line only
      LEFT  JOIN kna1 AS c ON c~kunnr = k~kunnr
      INTO CORRESPONDING FIELDS OF TABLE lt_raw
     WHERE k~vkorg IN s_vkorg
       AND k~kunnr IN s_kunnr
       AND k~audat IN s_audat
       AND p~gbsta <> 'C'.                             " Exclude fully delivered items

    IF sy-subrc <> 0.
      MESSAGE e001.
      RETURN.
    ENDIF.

    " Compute open quantity = ordered qty - already delivered qty
    LOOP AT lt_raw ASSIGNING FIELD-SYMBOL(<r>).
      <r>-offen = <r>-kwmeng - <r>-lfimg.
    ENDLOOP.

    APPEND LINES OF lt_raw TO mt_items.
    CALL METHOD me->compute_delay.
  ENDMETHOD.

  "--------------------------------------------------------------------
  " METHOD: COMPUTE_DELAY
  " Enriches each row with delay days, open value, status, icon, colour
  "--------------------------------------------------------------------
  METHOD compute_delay.
    LOOP AT mt_items ASSIGNING FIELD-SYMBOL(<fs>).

      <fs>-delay_d  = sy-datum - <fs>-edatu.
      <fs>-open_val = <fs>-offen * <fs>-netpr.

      CASE <fs>-delay_d.
        WHEN lc_neg TO 0.           " On schedule or future delivery
          <fs>-status   = 'Confirmed'.
          <fs>-icon_fld = icon_led_green.
          <fs>-row_col  = ''.
        WHEN 1 TO 7.                " 1-7 days overdue
          <fs>-status   = 'At Risk'.
          <fs>-icon_fld = icon_led_yellow.
          <fs>-row_col  = '53'.
        WHEN 8 TO 14.               " 8-14 days overdue
          <fs>-status   = 'Overdue'.
          <fs>-icon_fld = icon_led_red.
          <fs>-row_col  = '21'.
        WHEN OTHERS.                " More than 14 days overdue
          <fs>-status   = 'Critical'.
          <fs>-icon_fld = icon_failure.
          <fs>-row_col  = '21'.
      ENDCASE.

    ENDLOOP.
  ENDMETHOD.

  "--------------------------------------------------------------------
  " METHOD: BUILD_FIELDCAT
  " Constructs ALV field catalogue with hotspot, currency ref, labels
  "--------------------------------------------------------------------
  METHOD build_fieldcat.
    DATA ls_fc TYPE slis_fieldcat_alv.

    " Helper macro to append field catalogue entries
    DEFINE add_field.
      CLEAR ls_fc.
      ls_fc-fieldname  = &1.
      ls_fc-tabname    = 'GT_ITEMS'.
      ls_fc-coltext    = &2.
      ls_fc-outputlen  = &3.
      APPEND ls_fc TO gt_fieldcat.
    END-OF-DEFINITION.

    add_field 'VBELN'    'Sales Order'    10.
    add_field 'POSNR'    'Item'            6.
    add_field 'KUNNR'    'Customer'       10.
    add_field 'NAME1'    'Customer Name'  30.
    add_field 'VKORG'    'Sales Org'       5.
    add_field 'MATNR'    'Material'       18.
    add_field 'ARKTX'    'Description'    30.
    add_field 'KWMENG'   'Order Qty'      13.
    add_field 'OFFEN'    'Open Qty'       13.
    add_field 'OPEN_VAL' 'Open Value'     15.
    add_field 'WAERK'    'Currency'        5.
    add_field 'EDATU'    'Conf. Del. Date' 10.
    add_field 'AUDAT'    'Order Date'     10.
    add_field 'DELAY_D'  'Delay (Days)'   12.
    add_field 'STATUS'   'Status'         12.
    add_field 'ICON_FLD' 'Traffic Light'   4.

    " Set hotspot on Sales Order number for drill-down
    READ TABLE gt_fieldcat WITH KEY fieldname = 'VBELN'
      ASSIGNING FIELD-SYMBOL(<fc>).
    IF sy-subrc = 0.
      <fc>-hotspot = 'X'.
    ENDIF.

    " Bind currency reference for Open Value
    READ TABLE gt_fieldcat WITH KEY fieldname = 'OPEN_VAL'
      ASSIGNING FIELD-SYMBOL(<fv>).
    IF sy-subrc = 0.
      <fv>-ref_field = 'WAERK'.
      <fv>-ref_table = 'VBAK'.
    ENDIF.

    " Hide internal colour-code column from display
    READ TABLE gt_fieldcat WITH KEY fieldname = 'ROW_COL'
      ASSIGNING FIELD-SYMBOL(<fr>).
    IF sy-subrc = 0.
      <fr>-no_out = 'X'.
    ENDIF.
  ENDMETHOD.

  "--------------------------------------------------------------------
  " METHOD: SET_LAYOUT
  " Configures ALV grid layout: zebra, selection mode, row colouring
  "--------------------------------------------------------------------
  METHOD set_layout.
    gs_layout-zebra       = 'X'.   " Alternating row background
    gs_layout-sel_mode    = 'D'.   " Multiple row selection
    gs_layout-cwidth_opt  = 'X'.   " Auto-optimise column widths
    gs_layout-info_fname  = 'ROW_COL'. " Field name driving row colours
  ENDMETHOD.

  "--------------------------------------------------------------------
  " METHOD: DISPLAY_GRID
  " Creates docking container and ALV grid; wires event handlers
  "--------------------------------------------------------------------
  METHOD display_grid.

    " Anchor grid at bottom 90% of screen - no separate dynpro needed
    CREATE OBJECT go_container
      EXPORTING
        side  = cl_gui_docking_container=>dock_at_bottom
        ratio = 90.

    CREATE OBJECT go_grid
      EXPORTING i_parent = go_container.

    " Instantiate and register event handler
    DATA lo_hdl TYPE REF TO lcl_event_handler.
    CREATE OBJECT lo_hdl.
    SET HANDLER lo_hdl->on_double_click  FOR go_grid.
    SET HANDLER lo_hdl->on_toolbar_click FOR go_grid.

    " Bind sort with subtotals
    DATA: lt_sort TYPE slis_t_sortinfo_alv,
          ls_sort TYPE slis_sortinfo_alv.

    CLEAR ls_sort.
    ls_sort-fieldname = 'VKORG'. ls_sort-subtot = 'X'. ls_sort-spos = 1.
    APPEND ls_sort TO lt_sort.

    CLEAR ls_sort.
    ls_sort-fieldname = 'KUNNR'. ls_sort-subtot = 'X'. ls_sort-spos = 2.
    APPEND ls_sort TO lt_sort.

    CALL METHOD go_grid->set_table_for_first_display
      EXPORTING
        is_layout       = gs_layout
      CHANGING
        it_outtab       = mt_items
        it_fieldcatalog = gt_fieldcat.

  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* CLASS: LCL_EVENT_HANDLER IMPLEMENTATION
*----------------------------------------------------------------------*
CLASS lcl_event_handler IMPLEMENTATION.

  "--------------------------------------------------------------------
  " METHOD: ON_DOUBLE_CLICK
  " Opens VA03 with the clicked row's Sales Order + Item pre-populated
  "--------------------------------------------------------------------
  METHOD on_double_click.
    DATA ls TYPE ty_so_backlog.
    READ TABLE gt_items INDEX e_row-index INTO ls.
    CHECK sy-subrc = 0.

    SET PARAMETER ID 'AUN' FIELD ls-vbeln.  " Sales Order Number
    SET PARAMETER ID 'AUP' FIELD ls-posnr.  " Item Number
    CALL TRANSACTION 'VA03' AND SKIP FIRST SCREEN.
  ENDMETHOD.

  "--------------------------------------------------------------------
  " METHOD: ON_TOOLBAR_CLICK
  " Handles custom Refresh button ZB01 — confirms then re-reads data
  "--------------------------------------------------------------------
  METHOD on_toolbar_click.
    IF e_object-function = 'ZB01'.
      CALL FUNCTION 'POPUP_TO_CONFIRM'
        EXPORTING
          titlebar      = 'Refresh Backlog'
          text_question = 'Re-read data from SAP?'
        IMPORTING
          answer        = DATA(lv_ans).

      CHECK lv_ans = '1'.  " User confirmed

      CLEAR gt_items.

      DATA lo_app TYPE REF TO lcl_so_backlog.
      CREATE OBJECT lo_app.
      lo_app->get_open_orders( ).

      go_grid->refresh_table_display( ).
    ENDIF.
  ENDMETHOD.

ENDCLASS.

*&---------------------------------------------------------------------*
*& INCLUDE: ZSDSO_OUT — Main Program Entry Point
*&---------------------------------------------------------------------*

START-OF-SELECTION.

  DATA lo_app TYPE REF TO lcl_so_backlog.
  CREATE OBJECT lo_app.

  " Execute all layers in sequence
  lo_app->get_open_orders( ).
  lo_app->build_fieldcat( ).
  lo_app->set_layout( ).
  lo_app->display_grid( ).

*&---------------------------------------------------------------------*
*& DATA DICTIONARY OBJECTS (create separately in SE11)
*&---------------------------------------------------------------------*
*
*  Structure: ZSTR_SO_BACKLOG
*    → All 19 fields from ty_so_backlog above
*
*  Domain: ZDO_DLVRY_STATUS
*    → Data type: CHAR, Length: 12
*    → Fixed values: CONFIRMED / AT_RISK / OVERDUE / CRITICAL
*
*  Data Element: ZDE_DELAY_DAYS
*    → Domain: INT4
*    → Short text: 'Schedule Delay Days'
*
*&---------------------------------------------------------------------*
*& MESSAGE CLASS: ZSD_MSG (create in SE91)
*&---------------------------------------------------------------------*
*
*  001 → No open sales orders found
*  002 → Invalid delivery date range — start must precede end
*  003 → Sales organisation &1 not authorised
*
*&---------------------------------------------------------------------*
*& TRANSPORT: SE09 / STMS
*&---------------------------------------------------------------------*
*
*  Package: ZSD_DEV
*  Transport objects:
*    - Program:       ZSD_SO_BACKLOG + all includes
*    - DD Structure:  ZSTR_SO_BACKLOG
*    - DD Domain:     ZDO_DLVRY_STATUS
*    - DD Data Elem:  ZDE_DELAY_DAYS
*    - Message Class: ZSD_MSG
*  Transport landscape: DEV → QA → PRD
*
*&---------------------------------------------------------------------*
