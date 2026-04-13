# 보관함 관리 기능 설계

## 개요

페어(커플) 단위로 공유하는 보관함 관리 기능. 보관함별 구역을 나누고, 품목의 소비기한을 추적하여 알림을 보낸다.
보관함은 냉장고, 냉동고, 김치냉장고, 팬트리(식품장) 등 용도에 맞게 자유롭게 추가할 수 있다.

## 데이터 모델

### Storage (보관함)

| 필드 | 타입 | 설명 |
|------|------|------|
| id | Long | PK |
| pairId | Long | 페어 ID (공유 단위) |
| name | String(30) | 보관함 이름 (예: 냉장고, 냉동고, 김치냉장고, 팬트리) |
| sortOrder | Int | 정렬 순서 |

- 페어가 없는 사용자: userId로 소유
- 페어가 있는 사용자: pairId로 공유

### StorageSection (구역)

| 필드 | 타입 | 설명 |
|------|------|------|
| id | Long | PK |
| storageId | Long | FK → Storage |
| name | String(20) | 구역 이름 (예: 윗칸, 아랫칸, 야채칸, 선반1) |
| sortOrder | Int | 정렬 순서 |

### StorageItem (품목)

| 필드 | 타입 | 설명 |
|------|------|------|
| id | Long | PK |
| sectionId | Long | FK → StorageSection |
| name | String(30) | 품목 이름 |
| quantity | Int | 수량 (기본 1, 최소 0) |
| expiryDate | Date? | 소비기한 (nullable) |
| createdBy | Long | 등록한 사용자 ID |
| createdAt | DateTime | 등록일시 |

## API 엔드포인트

### 보관함 (Storage)

| Method | Path | 설명 |
|--------|------|------|
| GET | /storages | 보관함 목록 조회 (페어 공유 포함) |
| POST | /storages | 보관함 생성 (구역 포함) |
| PUT | /storages/{id} | 보관함 이름 수정 |
| DELETE | /storages/{id} | 보관함 삭제 (하위 구역, 품목 전부 삭제) |

### 구역 (Section)

| Method | Path | 설명 |
|--------|------|------|
| POST | /storages/{id}/sections | 구역 추가 |
| PUT | /storages/{id}/sections/{sectionId} | 구역 이름 수정 |
| DELETE | /storages/{id}/sections/{sectionId} | 구역 삭제 (하위 품목 전부 삭제) |

### 품목 (Item)

| Method | Path | 설명 |
|--------|------|------|
| GET | /storages/{id}/items | 해당 보관함의 전체 품목 조회 (구역별 그룹) |
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
              "quantity": 2,
              "expiryDate": "2026-04-08",
              "createdBy": 1,
              "createdAt": "2026-04-05T10:00:00"
            }
          ]
        }
      ]
    },
    {
      "id": 2,
      "name": "팬트리",
      "sortOrder": 3,
      "sections": [
        {
          "id": 5,
          "name": "선반1",
          "sortOrder": 0,
          "items": [
            {
              "id": 10,
              "name": "라면",
              "quantity": 5,
              "expiryDate": "2026-12-01",
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

### 1. 보관함 메인 화면

- **상단 탭**: 보관함별 전환 (스크롤 가능한 세그먼트 컨트롤)
- **경고 배너**: 소비기한 D-3 이하 품목 수 표시 (있을 때만)
- **구역별 섹션**: 접기/펼치기 가능한 카드
  - 섹션 헤더: 구역 이름 + 품목 수 + 추가 버튼
  - 품목 목록: 첫 글자 원형 아이콘 + 이름 + 수량(+/- 스테퍼) + D-day 뱃지
  - `-` 눌러서 수량이 0이 되면 삭제 확인 다이얼로그 표시 → 확인 시 삭제
- **네비게이션 바**: 타이틀 "보관함 관리" + 보관함 설정 버튼

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
- 수량 (숫자 스테퍼, 기본 1, 최소 1)
- 소비기한 (선택, DatePicker)
- 구역 선택 (해당 보관함의 구역 목록에서 선택)

### 5. 보관함 추가 시트

- 보관함 이름 입력
- 구역 목록 편집 (추가/삭제/이름변경, 드래그 정렬)

### 6. 보관함 설정 시트

- 보관함 이름 변경
- 구역 관리 (추가/삭제/이름변경)
- 보관함 삭제 (확인 다이얼로그)

## 알림

- **소비기한 D-3**: 로컬 알림 "OO의 소비기한이 3일 남았습니다"
- **소비기한 D-day**: 로컬 알림 "OO의 소비기한이 오늘입니다"
- 매일 오전 9시에 체크하여 알림 스케줄링

## 네비게이션

SideDrawerView에 "보관함 관리" 메뉴 항목 추가.
AppDestination enum에 `.storage` case 추가.

## 파일 구조

```
WooriHaru/
├── Models/
│   └── StorageModels.swift          # Storage, Section, Item 모델
├── Services/
│   └── StorageService.swift         # API 통신
├── ViewModels/
│   └── StorageViewModel.swift       # 상태 관리
└── Views/
    └── Storage/
        ├── StorageMainView.swift     # 메인 화면 (탭 + 구역 목록)
        ├── StorageItemRow.swift      # 품목 행 컴포넌트
        ├── StorageItemSheet.swift    # 품목 추가/수정 시트
        ├── StorageSettingSheet.swift # 보관함 추가/설정 시트
        └── InitialIconView.swift    # 첫 글자 원형 아이콘
```

## 페어 공유 규칙

- 보관함은 페어 단위로 공유 (pairId 기준)
- 페어가 없으면 개인 소유 (userId 기준)
- 페어 연결 시 기존 개인 보관함을 페어로 이관
- 페어 해제 시 보관함은 생성자에게 귀속
- 누가 등록했는지 createdBy로 추적 (UI에서는 별도 표시 안 함)
