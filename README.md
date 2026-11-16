# sap-basis-lab
SAP Basis project notes, tools and automation scripts for ECC &amp; S/4HANA

SAP Basis 운영과 프로젝트에서 직접 만들어 쓰는 ABAP 프로그램, DB 스크립트, 작업 기록을 정리합니다.

## Repository Structure

| 폴더 | 내용 |
|---|---|
| [`db/`](db/) | DB 운영 스크립트: 백업, 공간 관리, 점검 ([MSSQL](db/mssql/) · [HANA](db/hana/) · [Oracle](db/oracle/)) |
| [`basis/`](basis/) | Basis 일상 운영: 트랜스포트, 클라이언트 카피, 커널 패치, 사용자·권한 관리 |
| [`projects/`](projects/) | 프로젝트 수행 기록: 업그레이드, 마이그레이션, 시스템 구축 |
| [`troubleshooting/`](troubleshooting/) | 장애 대응 사례: 증상, 원인 분석, 조치 |
| [`sap-programs/`](sap-programs/) | 운영 자동화를 위한 ABAP 프로그램 |

## Contents

### DB

| 작업 | 설명 |
|---|---|
| [MSSQL 백업 구성 및 자동 삭제](db/mssql/backup-cleanup/) | Maintenance Plan으로 매일 Full·Log 백업, SQL Agent Job으로 지난 백업 자동 삭제 |

### SAP Programs

| 프로그램 | 설명 |
|---|---|
| [`ZBC_USER_PWD_RESET`](sap-programs/user-password-reset/) | 여러 사용자의 초기 비밀번호를 일괄 설정. 테스트 실행으로 대상을 확인한 뒤 실제 변경, 비밀번호 오류 잠금 자동 해제 |
