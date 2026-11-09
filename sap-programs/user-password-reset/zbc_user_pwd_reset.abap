REPORT zbc_user_pwd_reset.

* Reset explicitly selected dialog users in the current client only.
* No password literals or direct password-table updates.
* Unlocks only wrong-password locks (UFLAG 128); admin locks (32/64) stay.
* Flow:
*   screen 1000: users + password, F8
*   screen 200 : (테스트) result ALV + counts, nothing changed yet
*                F8(실행) -> confirm popup -> real change
*                -> same screen shows (실행 결과) + counts of changed users
* Screen 200 is a code-defined selection screen (no SE51 dynpro / GUI status needed).
TYPE-POOLS icon.
TABLES: sscrfields, usr02.

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE t_b01.
  SELECT-OPTIONS s_user FOR usr02-bname NO INTERVALS MODIF ID obl.
  PARAMETERS p_pwd TYPE bapipwd-bapipwd LOWER CASE MODIF ID obl.
SELECTION-SCREEN END OF BLOCK b1.

* 결과 화면 (테스트 / 실행 결과)
SELECTION-SCREEN BEGIN OF SCREEN 200 TITLE t_200.
  SELECTION-SCREEN COMMENT /1(79) c_sum1.
  SELECTION-SCREEN COMMENT /1(79) c_sum2.
SELECTION-SCREEN END OF SCREEN 200.

TYPES: BEGIN OF ty_result,
         icon      TYPE icon_d,
         username  TYPE usr02-bname,
         name      TYPE user_addr-name_textc,
         usergroup TYPE usr02-class,
         lock_txt  TYPE char20,
         valid_txt TYPE char30,
         uflag     TYPE usr02-uflag,
         warn      TYPE abap_bool,
         status    TYPE char10,
         message   TYPE bapi_msg,
       END OF ty_result,
       ty_users TYPE STANDARD TABLE OF usr02-bname WITH DEFAULT KEY.
* NOTE: RETURN must be a standard table with default key.
*       "WITH EMPTY KEY" dumps in BAPI_USER_CHANGE (PERFORM_CONFLICT_TAB_TYPE).
DATA: gt_result TYPE STANDARD TABLE OF ty_result,
      gt_return TYPE STANDARD TABLE OF bapiret2,
      gv_mode   TYPE c LENGTH 1,        "T = 테스트, R = 실행 완료
      gv_redraw TYPE abap_bool,
      go_dock   TYPE REF TO cl_gui_docking_container,
      go_alv    TYPE REF TO cl_salv_table,
      BEGIN OF gs_cnt,
        all    TYPE i,   "전체 입력 대상
        ready  TYPE i,   "변경 대상 (테스트)
        unlock TYPE i,   "잠금 해제 예정 / 해제됨
        suc    TYPE i,   "변경 성공
        err    TYPE i,   "실패
        skip   TYPE i,   "제외 / 미처리
      END OF gs_cnt.

INITIALIZATION.
  t_b01  = '비밀번호 초기화'.
* Selection texts set at runtime (standard layout)
  %_s_user_%_app_%-text = '사용자'.
  %_p_pwd_%_app_%-text  = '새 비밀번호'.
  PERFORM restrict_eq_only.

AT SELECTION-SCREEN OUTPUT.
  IF sy-dynnr = '0200'.
    PERFORM show_alv.
  ELSE.
    LOOP AT SCREEN.
      IF screen-group1 = 'OBL'.
        screen-required = '2'.   "필수 표시만 (F4/다중선택 막지 않음)
        MODIFY SCREEN.
      ENDIF.
    ENDLOOP.
  ENDIF.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR s_user-low.
  PERFORM user_help.

AT SELECTION-SCREEN.
  IF sy-dynnr = '0200'.
    IF sscrfields-ucomm = 'CRET' AND gv_mode = 'R'.
      MESSAGE '이미 실행했습니다. 뒤로(F3) 후 다시 진행해 주세요.' TYPE 'S' DISPLAY LIKE 'W'.
      CLEAR sscrfields-ucomm.      "결과 화면에 머무름
    ENDIF.
    RETURN.
  ENDIF.
  IF sscrfields-ucomm = 'ONLI'.
    PERFORM check_input.
  ENDIF.

START-OF-SELECTION.
  DATA lv_ok TYPE abap_bool.

* 1) 테스트: 대상 확인만
  PERFORM build_result.
  gv_mode = 'T'.

  DO.
    PERFORM set_summary.
    gv_redraw = abap_true.
    CALL SELECTION-SCREEN 200.        "F8 = 실행, F3 = 뒤로
    IF sy-subrc <> 0 OR gv_mode = 'R'.
      EXIT.
    ENDIF.
* 2) 실행
    PERFORM confirm_run CHANGING lv_ok.
    IF lv_ok = abap_false.
      MESSAGE '취소했습니다. 변경하지 않았습니다.' TYPE 'S'.
      CONTINUE.
    ENDIF.
    PERFORM execute_real.
    gv_mode = 'R'.
  ENDDO.
  CLEAR p_pwd.

*&---------------------------------------------------------------------*
FORM check_input.
  IF sy-batch = abap_true.
    MESSAGE '화면에서 직접 실행해 주세요. 백그라운드 실행은 지원하지 않습니다.' TYPE 'E'.
  ENDIF.
  IF s_user[] IS INITIAL.
    MESSAGE '변경할 사용자를 입력해 주세요.' TYPE 'E'.
  ENDIF.
  LOOP AT s_user TRANSPORTING NO FIELDS
       WHERE option <> 'EQ' OR low IS INITIAL OR ( sign <> 'I' AND sign <> 'E' ).
    MESSAGE '사용자 ID를 개별 값으로 입력해 주세요. 범위·패턴은 사용할 수 없습니다.' TYPE 'E'.
  ENDLOOP.
  LOOP AT s_user TRANSPORTING NO FIELDS WHERE sign = 'I'.
    EXIT.
  ENDLOOP.
  IF sy-subrc <> 0.
    MESSAGE '변경할 사용자를 1명 이상 입력해 주세요 (제외만 입력됨).' TYPE 'E'.
  ENDIF.
  IF p_pwd IS INITIAL.
    MESSAGE '새 비밀번호를 입력해 주세요.' TYPE 'E'.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
FORM confirm_run CHANGING cv_ok TYPE abap_bool.
  DATA: lv_answer   TYPE c LENGTH 1,
        lv_question TYPE string.

  cv_ok = abap_false.
  IF gs_cnt-ready = 0.
    MESSAGE '변경 가능한 대상이 없습니다.' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.
  lv_question = |{ sy-sysid }/{ sy-mandt } 에서 { gs_cnt-ready }명의 비밀번호를 실제로 변경합니다. 진행할까요?|.
  CALL FUNCTION 'POPUP_TO_CONFIRM'
    EXPORTING
      titlebar              = '비밀번호 초기화 실행'
      text_question         = lv_question
      text_button_1         = '실행'
      text_button_2         = '취소'
      default_button        = '2'
      display_cancel_button = space
    IMPORTING
      answer                = lv_answer
    EXCEPTIONS
      OTHERS                = 1.
  IF sy-subrc = 0 AND lv_answer = '1'.
    cv_ok = abap_true.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
* 실제 변경 (테스트와 같은 입력, 실행 직전 상태로 다시 검사)
FORM execute_real.
  DATA: ls_password TYPE bapipwd,
        ls_pwdx     TYPE bapipwdx,
        ls_commit   TYPE bapiret2,
        lv_failed   TYPE abap_bool,
        lv_errmsg   TYPE bapi_msg.

  PERFORM build_result.
  ls_password-bapipwd = p_pwd.
  ls_pwdx-bapipwd     = abap_true.
  CLEAR p_pwd.

  LOOP AT gt_result ASSIGNING FIELD-SYMBOL(<result>) WHERE status = 'READY'.
    CLEAR: gt_return, lv_failed, ls_commit, lv_errmsg.
    CALL FUNCTION 'BAPI_USER_CHANGE'
      EXPORTING
        username       = <result>-username
        password       = ls_password
        passwordx      = ls_pwdx
        productive_pwd = space
      TABLES
        return         = gt_return.
    LOOP AT gt_return ASSIGNING FIELD-SYMBOL(<message>) WHERE type CA 'AEX'.
      lv_failed = abap_true.
      lv_errmsg = <message>-message.
      EXIT.
    ENDLOOP.
* Wrong-password lock only (128 set, no admin lock 32/64) -> unlock
    IF lv_failed = abap_false AND <result>-uflag >= 128
       AND <result>-uflag MOD 128 < 32.
      CLEAR gt_return.
      CALL FUNCTION 'BAPI_USER_UNLOCK'
        EXPORTING
          username = <result>-username
        TABLES
          return   = gt_return.
      LOOP AT gt_return ASSIGNING <message> WHERE type CA 'AEX'.
        lv_failed = abap_true.
        lv_errmsg = |잠금 해제 실패: { <message>-message }|.
        EXIT.
      ENDLOOP.
    ENDIF.
    IF lv_failed = abap_true.
      CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
      <result>-status  = 'ERROR'.
      <result>-message = lv_errmsg.
      CONTINUE.
    ENDIF.
    CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
      EXPORTING
        wait   = abap_true
      IMPORTING
        return = ls_commit.
    IF ls_commit-type CA 'AEX'.
      <result>-status  = 'UNKNOWN'.
      <result>-message = '저장 결과를 확인할 수 없습니다. SU01에서 확인해 주세요.'.
* Do not continue after an ambiguous commit outcome.
      EXIT.
    ENDIF.
    <result>-status = 'SUCCESS'.
    IF <result>-uflag >= 128 AND <result>-uflag MOD 128 < 32.
      <result>-lock_txt = '해제됨'.
      <result>-message  = '비밀번호 변경 + 잠금 해제 완료'.
    ELSE.
      <result>-message  = '비밀번호 변경 완료'.
    ENDIF.
    IF <result>-uflag MOD 128 >= 32.
      <result>-message = |{ <result>-message } / 관리자 잠금은 유지|.
    ENDIF.
    IF <result>-valid_txt IS NOT INITIAL.
      <result>-message = |{ <result>-message } / 효력기간 확인 필요(SU01)|.
    ENDIF.
  ENDLOOP.
  CLEAR: ls_password, ls_pwdx, gt_return.
  LOOP AT gt_result ASSIGNING <result> WHERE status = 'READY'.
    <result>-status  = 'NOT_RUN'.
    <result>-message = '앞선 저장 오류로 처리하지 않았습니다.'.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
* 건수 집계 + 결과 화면 제목/요약
FORM set_summary.
  CLEAR gs_cnt.
  LOOP AT gt_result ASSIGNING FIELD-SYMBOL(<r>).
    gs_cnt-all = gs_cnt-all + 1.
    CASE <r>-status.
      WHEN 'READY'.
        gs_cnt-ready = gs_cnt-ready + 1.
        IF <r>-uflag >= 128 AND <r>-uflag MOD 128 < 32.
          gs_cnt-unlock = gs_cnt-unlock + 1.
        ENDIF.
      WHEN 'SUCCESS'.
        gs_cnt-suc = gs_cnt-suc + 1.
        IF <r>-lock_txt = '해제됨'.
          gs_cnt-unlock = gs_cnt-unlock + 1.
        ENDIF.
      WHEN 'ERROR' OR 'UNKNOWN'.
        gs_cnt-err = gs_cnt-err + 1.
      WHEN OTHERS.
        gs_cnt-skip = gs_cnt-skip + 1.
    ENDCASE.
  ENDLOOP.

  IF gv_mode = 'T'.
    t_200  = |{ sy-sysid }/{ sy-mandt } 비밀번호 초기화 (테스트)|.
    c_sum1 = |(테스트) 총 { gs_cnt-all }명 중 변경 대상 { gs_cnt-ready }명 / 제외 { gs_cnt-skip }명 / 잠금 해제 예정 { gs_cnt-unlock }명|.
    c_sum2 = '아직 변경하지 않았습니다. 확인 후 실행(F8)을 누르세요. 취소는 뒤로(F3).'.
    MESSAGE |(테스트) 변경 대상 { gs_cnt-ready }명 - 실행(F8)을 눌러야 실제 변경됩니다.| TYPE 'S'.
  ELSE.
    t_200  = |{ sy-sysid }/{ sy-mandt } 비밀번호 초기화 (실행 결과)|.
    c_sum1 = |총 { gs_cnt-suc }명 변경 완료 (잠금 해제 { gs_cnt-unlock }명) / 실패 { gs_cnt-err }명 / 제외 { gs_cnt-skip }명|.
    c_sum2 = '뒤로(F3)를 누르면 첫 화면으로 돌아갑니다.'.
    MESSAGE |총 { gs_cnt-suc }명 변경 완료 / 실패 { gs_cnt-err }명 / 제외 { gs_cnt-skip }명| TYPE 'S'.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
* 대상 = 포함(I) - 제외(E), 정렬·중복 제거
FORM get_target_users CHANGING ct_users TYPE ty_users.
  CLEAR ct_users.
  LOOP AT s_user WHERE sign = 'I'.
    READ TABLE s_user TRANSPORTING NO FIELDS
      WITH KEY sign = 'E' low = s_user-low.
    IF sy-subrc <> 0.
      APPEND s_user-low TO ct_users.
    ENDIF.
  ENDLOOP.
  SORT ct_users.
  DELETE ADJACENT DUPLICATES FROM ct_users.
ENDFORM.

*&---------------------------------------------------------------------*
FORM restrict_eq_only.
  DATA: ls_restrict TYPE sscr_restrict,
        ls_opt      TYPE sscr_opt_list,
        ls_ass      TYPE sscr_ass.

  ls_opt-name       = 'EQ_ONLY'.
  ls_opt-options-eq = abap_true.
  APPEND ls_opt TO ls_restrict-opt_list_tab.

  ls_ass-kind    = 'S'.
  ls_ass-name    = 'S_USER'.
  ls_ass-sg_main = '*'.   "포함(I) + 제외(E)
  ls_ass-op_main = 'EQ_ONLY'.
  APPEND ls_ass TO ls_restrict-ass_tab.

  CALL FUNCTION 'SELECT_OPTIONS_RESTRICT'
    EXPORTING
      restriction            = ls_restrict
    EXCEPTIONS
      too_late               = 1
      repeated               = 2
      selopt_without_options = 3
      selopt_without_signs   = 4
      invalid_sign           = 5
      empty_option_list      = 6
      invalid_kind           = 7
      repeated_kind_a        = 8
      OTHERS                 = 9.
ENDFORM.

*&---------------------------------------------------------------------*
FORM build_result.
  DATA: lt_users  TYPE ty_users,
        ls_result TYPE ty_result.

  CLEAR gt_result.
  PERFORM get_target_users CHANGING lt_users.
  LOOP AT lt_users INTO DATA(lv_user).
    CLEAR ls_result.
    ls_result-username = lv_user.
    PERFORM check_target CHANGING ls_result.
    APPEND ls_result TO gt_result.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
FORM check_target CHANGING cs_result TYPE ty_result.
  DATA: lv_type  TYPE usr02-ustyp,
        lv_group TYPE usr02-class,
        lv_from  TYPE usr02-gltgv,
        lv_to    TYPE usr02-gltgb.

  cs_result-status = 'SKIPPED'.
  SELECT SINGLE name_textc FROM user_addr
    WHERE bname = @cs_result-username
    INTO @cs_result-name.

  IF cs_result-username = sy-uname
     OR cs_result-username = 'SAP*'
     OR cs_result-username = 'DDIC'
     OR cs_result-username = 'SAPCPIC'
     OR cs_result-username = 'EARLYWATCH'
     OR cs_result-username = 'TMSADM'.
    cs_result-message = '본인 계정 또는 보호 대상 표준 계정이라 제외'.
    RETURN.
  ENDIF.
  SELECT SINGLE ustyp, class, uflag, gltgv, gltgb FROM usr02
    WHERE bname = @cs_result-username
    INTO (@lv_type, @lv_group, @cs_result-uflag, @lv_from, @lv_to).
  IF sy-subrc <> 0.
    cs_result-message = '현재 클라이언트에 없는 사용자'.
    RETURN.
  ENDIF.
  cs_result-usergroup = lv_group.

* 잠금 상태
  IF cs_result-uflag MOD 128 >= 32.
    cs_result-lock_txt = '관리자 잠금'.
    cs_result-warn     = abap_true.
  ELSEIF cs_result-uflag >= 128.
    cs_result-lock_txt = '비밀번호 오류 잠금'.
  ENDIF.

* 효력기간 (자동 연장하지 않고 표시만)
  IF lv_to IS NOT INITIAL AND lv_to < sy-datum.
    cs_result-valid_txt = |만료 ({ lv_to DATE = USER })|.
    cs_result-warn      = abap_true.
  ELSEIF lv_from IS NOT INITIAL AND lv_from > sy-datum.
    cs_result-valid_txt = |시작 전 ({ lv_from DATE = USER })|.
    cs_result-warn      = abap_true.
  ENDIF.

  AUTHORITY-CHECK OBJECT 'S_USER_GRP'
    ID 'CLASS' FIELD lv_group
    ID 'ACTVT' FIELD '05'.
  IF sy-subrc <> 0.
    cs_result-message = '이 사용자 그룹의 변경 권한 없음 (S_USER_GRP/05)'.
    RETURN.
  ENDIF.
  IF lv_type <> 'A'.
    cs_result-message = '대화형 사용자(유형 A)만 변경 가능'.
    RETURN.
  ENDIF.

  cs_result-status  = 'READY'.
  cs_result-message = '(테스트) 변경 대상'.
  IF cs_result-uflag MOD 128 >= 32.
    cs_result-message = |{ cs_result-message } / 관리자 잠금은 해제하지 않음|.
  ELSEIF cs_result-uflag >= 128.
    cs_result-message = |{ cs_result-message } / 잠금 해제 예정|.
  ENDIF.
  IF cs_result-valid_txt IS NOT INITIAL.
    cs_result-message = |{ cs_result-message } / 효력기간 밖이라 변경해도 로그인 불가 (SU01에서 기간 조정)|.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
* 결과 ALV (결과 화면 200 의 docking container)
FORM show_alv.
  DATA: lo_columns TYPE REF TO cl_salv_columns_table,
        lo_icon    TYPE REF TO cl_salv_column_table,
        lx_salv    TYPE REF TO cx_salv_error,
        lv_header  TYPE lvc_title,
        lv_first   TYPE abap_bool.

  CHECK gv_redraw = abap_true.
  CLEAR gv_redraw.

  LOOP AT gt_result ASSIGNING FIELD-SYMBOL(<row>).
    CASE <row>-status.
      WHEN 'READY' OR 'SUCCESS'.
        <row>-icon = COND #( WHEN <row>-warn = abap_true THEN icon_led_yellow
                                                        ELSE icon_led_green ).
      WHEN 'ERROR' OR 'UNKNOWN'.
        <row>-icon = icon_led_red.
      WHEN OTHERS.            "SKIPPED / NOT_RUN
        <row>-icon = icon_led_inactive.
    ENDCASE.
  ENDLOOP.

  lv_header = t_200.
  TRY.
      IF go_alv IS INITIAL.
        lv_first = abap_true.
        go_dock = NEW #( repid = sy-repid
                         dynnr = sy-dynnr
                         side  = cl_gui_docking_container=>dock_at_bottom
                         ratio = 88 ).
        cl_salv_table=>factory(
          EXPORTING r_container  = go_dock
          IMPORTING r_salv_table = go_alv
          CHANGING  t_table      = gt_result ).

        go_alv->get_functions( )->set_default( abap_true ).
        lo_columns = go_alv->get_columns( ).
        lo_icon ?= lo_columns->get_column( 'ICON' ).
        lo_icon->set_icon( abap_true ).
        PERFORM set_col USING lo_columns: 'ICON'      '상태'        6,
                                          'USERNAME'  '사용자'      14,
                                          'NAME'      '이름'        20,
                                          'USERGROUP' '사용자그룹'  12,
                                          'LOCK_TXT'  '잠금'        16,
                                          'VALID_TXT' '효력기간'    20,
                                          'MESSAGE'   '메시지'      80.
        lo_columns->get_column( 'STATUS' )->set_technical( abap_true ).
        lo_columns->get_column( 'UFLAG' )->set_technical( abap_true ).
        lo_columns->get_column( 'WARN' )->set_technical( abap_true ).
      ENDIF.

      go_alv->get_display_settings( )->set_list_header( lv_header ).
      IF lv_first = abap_true.
        go_alv->display( ).
      ELSE.
        go_alv->refresh( refresh_mode = if_salv_c_refresh=>full ).
      ENDIF.
    CATCH cx_salv_error INTO lx_salv.
      MESSAGE lx_salv->get_text( ) TYPE 'S' DISPLAY LIKE 'E'.
  ENDTRY.
ENDFORM.

*&---------------------------------------------------------------------*
FORM set_col USING io_columns TYPE REF TO cl_salv_columns_table
                   iv_field   TYPE csequence
                   iv_text    TYPE csequence
                   iv_len     TYPE i
             RAISING cx_salv_not_found.
  DATA(lo_col) = io_columns->get_column( CONV #( iv_field ) ).
  lo_col->set_short_text( CONV #( iv_text ) ).
  lo_col->set_medium_text( CONV #( iv_text ) ).
  lo_col->set_long_text( CONV #( iv_text ) ).
  lo_col->set_output_length( CONV #( iv_len ) ).
ENDFORM.

*&---------------------------------------------------------------------*
FORM user_help.
  TYPES: BEGIN OF ty_user_help,
           bname TYPE usr02-bname,
           name  TYPE user_addr-name_textc,
           class TYPE usr02-class,
           gltgb TYPE usr02-gltgb,
         END OF ty_user_help.
  DATA lt_users TYPE STANDARD TABLE OF ty_user_help.

  SELECT a~bname, b~name_textc AS name, a~class, a~gltgb
    FROM usr02 AS a LEFT OUTER JOIN user_addr AS b
      ON a~bname = b~bname
   WHERE a~ustyp = 'A'
    INTO CORRESPONDING FIELDS OF TABLE @lt_users.

  LOOP AT lt_users ASSIGNING FIELD-SYMBOL(<user>).
    AUTHORITY-CHECK OBJECT 'S_USER_GRP'
      ID 'CLASS' FIELD <user>-class
      ID 'ACTVT' FIELD '05'.
    IF sy-subrc <> 0.
      DELETE lt_users.
    ENDIF.
  ENDLOOP.
  SORT lt_users BY bname.
  DELETE ADJACENT DUPLICATES FROM lt_users COMPARING bname.

  CALL FUNCTION 'F4IF_INT_TABLE_VALUE_REQUEST'
    EXPORTING
      retfield        = 'BNAME'
      dynpprog        = sy-repid
      dynpnr          = sy-dynnr
      dynprofield     = 'S_USER-LOW'
      window_title    = '사용자 선택'
      value_org       = 'S'
    TABLES
      value_tab       = lt_users
    EXCEPTIONS
      parameter_error = 1
      no_values_found = 2
      OTHERS          = 3.
  IF sy-subrc <> 0.
    MESSAGE '조회 가능한 사용자가 없습니다.' TYPE 'S'.
  ENDIF.
ENDFORM.
