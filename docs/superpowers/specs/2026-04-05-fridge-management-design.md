# 냉장고 관리 기능 설계

## 개요

페어(커플) 단위로 공유하는 냉장고 관리 기능. 냉장고별 구역을 나누고, 품목의 소비기한을 추적하여 알림을 보낸다.

## 데이터 모델

### Storage (냉장고)

| 필드 | 타입 | 설명 |
|------|------|------|
| id | Long | PK |
| pairId | Long | 페어 ID (공유 단위) |
| name | String(30) | 냉장고 이름 (예: 냉장고, 냉동고, 김치냉장고) |
| sortOrder | Int | 정렬 순서 |

- 페어가 없는 사용자: userId로 소유
- 페어가 있는 사용자: pairId로 공유

### StorageSection (구역)

| 필드 | 타입 | 설명 |
|------|------|------|
| id | Long | PK |
| storageId | Long | FK → Storage |
| name | String(20) | 구역 이름 (예: 윗칸, 아랫칸, 야채칸) |
| sortOrder | Int | 정렬 순서 |

### StorageItem (품목)

| 필드 | 타입 | 설명 |
|------|------|------|
| id | Long | PK |
| sectionId | Long | FK → StorageSection |
| name | String(30) | 품목 이름 |
| quantity | String(20) | 수량 (자유 입력: "2개", "1팩", "30구") |
| expiryDate | Date? | 소비기한 (nullable) |
| createdBy | Long | 등록한 사용자 ID |
| createdAt | DateTime | 등록일시 |

## API 엔드포인트

### 냉장고 (Storage)

| Method | Path | 설명 |
|--------|------|------|
| GET | /storages | 냉장고 목록 조회 (페어 공유 포함) |
| POST | /storages | 냉장고 생성 (구역 포함) |
| PUT | /storages/{id} | 냉장고 이름 수정 |
| DELETE | /storages/{id} | 냉장고 삭제 (하위 구역, 품목 전부 삭제) |

### 구역 (Section)

| Method | Path | 설명 |
|--------|------|------|
| POST | /storages/{id}/sections | 구역 추가 |
| PUT | /storages/{id}/sections/{sectionId} | 구역 이름 수정 |
| DELETE | /storages/{id}/sections/{sectionId} | 구역 삭제 (하위 품목 전부 삭제) |

### 품목 (Item)

| Method | Path | 설명 |
|--------|------|------|
| GET | /storages/{id}/items | 해당 냉장고의 전체 품목 조회 (구역별 그룹) |
| POST | /storages/{id}/items | 품목 추가 |
| PUT | /storages/{id}/items/{itemId} | 품목 수정 |
| DELETE | /storages/{id}/items/{itemId} | 품목 삭제 |

### 응답 구조 예시

GET /storages 응답:
```json
{
  "data": [
    {
      "id": 1,
      "name": "냉장고",
      "sortOrder": 0,
      "sections": [
        {
          "id": 1,
          "name": "윗칸",
          "sortOrder": 0,
          "items": [
            {
              "id": 1,
              "name": "우유",
              "quantity": "2개",
              "expiryDate": "2026-04-08",
              "createdBy": 1,
              "createdAt": "2026-04-05T10:00:00"
            }
          ]
        }
      ]
    }
  ]
}
```

## iOS 화면 구성

### 1. 냉장고 메인 화면

- **상단 탭**: 냉장고별 전환 (세그먼트 컨트롤)
- **경고 배너**: 소비기한 D-3 이하 품목 수 표시 (있을 때만)
- **구역별 섹션**: 접기/펼치기 가능한 카드
  - 섹션 헤더: 구역 이름 + 품목 수 + 추가 버튼
  - 품목 목록: 첫 글자 원형 아이콘 + 이름 + 수량 + D-day 뱃지
- **네비게이션 바**: 타이틀 "냉장고 관리" + 냉장고 설정 버튼

### 2. 품목 아이콘

이모지 대신 **이름 첫 글자를 컬러 원형 아이콘**으로 표시.
색상은 첫 글자의 유니코드 값 기반으로 6가지 색상 중 자동 배정.

### 3. D-day 뱃지 색상

| 조건 | 색상 | 표시 |
|------|------|------|
| 기한 없음 | 회색 | "기한 없음" |
| D-day 이후 (만료) | 빨강 (진) | "D+N" |
| D-1 ~ D-3 | 빨강 | "D-N" |
| D-4 ~ D-7 | 주황 | "D-N" |
| D-8 이상 | 초록 | "D-N" |

### 4. 품목 추가 시트

- 이름 (필수, 텍스트 입력)
- 수량 (선택, 기본 "1개")
- 소비기한 (선택, DatePicker)
- 구역 선택 (해당 냉장고의 구역 목록에서 선택)

### 5. 냉장고 추가 시트

- 냉장고 이름 입력
- 구역 목록 편집 (추가/삭제/이름변경, 드래그 정렬)

### 6. 냉장고 설정 시트

- 냉장고 이름 변경
- 구역 관리 (추가/삭제/이름변경)
- 냉장고 삭제 (확인 다이얼로그)

## 알림

- **소비기한 D-3**: 로컬 알림 "OO의 소비기한이 3일 남았습니다"
- **소비기한 D-day**: 로컬 알림 "OO의 소비기한이 오늘입니다"
- 매일 오전 9시에 체크하여 알림 스케줄링

## 네비게이션

SideDrawerView에 "냉장고 관리" 메뉴 항목 추가.
AppDestination enum에 `.fridge` case 추가.

## 파일 구조

```
WooriHaru/
├── Models/
│   └── FridgeModels.swift          # Storage, Section, Item 모델
├── Services/
│   └── FridgeService.swift         # API 통신
├── ViewModels/
│   └── FridgeViewModel.swift       # 상태 관리
└── Views/
    └── Fridge/
        ├── FridgeMainView.swift     # 메인 화면 (탭 + 구역 목록)
        ├── FridgeItemRow.swift      # 품목 행 컴포넌트
        ├── FridgeItemSheet.swift    # 품목 추가/수정 시트
        ├── FridgeStorageSheet.swift # 냉장고 추가/설정 시트
        └── InitialIconView.swift   # 첫 글자 원형 아이콘
```

## 페어 공유 규칙

- 냉장고는 페어 단위로 공유 (pairId 기준)
- 페어가 없으면 개인 소유 (userId 기준)
- 페어 연결 시 기존 개인 냉장고를 페어로 이관
- 페어 해제 시 냉장고는 생성자에게 귀속
- 누가 등록했는지 createdBy로 추적 (UI에서는 별도 표시 안 함)
