#pragma once

// String IDs
#define IDS_LIBDESCRIPTION          1
#define IDS_CATEGORY                2
#define IDS_CLASS_NAME              3
#define IDS_PARAMS                  4

#define IDS_ROL_PATTERN             10
#define IDS_ROL_BOARDSIZE           11
#define IDS_ROL_VARIATION           12
#define IDS_ROL_GENERAL             13
#define IDS_ROL_UV                  14
#define IDS_ROL_WARNINGS            15
#define IDS_ROL_UPDATE              16
#define IDS_ROL_PRESETS             17
#define IDS_ROL_CREDITS             18
#define IDS_ROL_BORDER              19
#define IDS_SUB_BORDER_LINES        20

// Dialog IDs (10 Collapsible Rollouts)
#define IDD_PANEL_PATTERN           101
#define IDD_PANEL_BOARDSIZE         102
#define IDD_PANEL_VARIATION         103
#define IDD_PANEL_GENERAL           104
#define IDD_PANEL_UV                105
#define IDD_PANEL_WARNINGS          106
#define IDD_PANEL_UPDATE            107
#define IDD_PANEL_PRESETS           108
#define IDD_PANEL_CREDITS           109
#define IDD_PANEL_BORDER            110

// Pattern controls
#define IDC_PAT_COMBO               1001
#define IDC_PAT_PARALLELS_EDIT      1002
#define IDC_PAT_PARALLELS_SPIN      1003
#define IDC_PAT_CHEVRON_EDIT        1004
#define IDC_PAT_CHEVRON_SPIN        1005
#define IDC_PAT_SUBBOARDS_EDIT      1006
#define IDC_PAT_SUBBOARDS_SPIN      1007
#define IDC_PAT_INSERTSIZE_EDIT     1008
#define IDC_PAT_INSERTSIZE_SPIN     1009
#define IDC_PAT_DYN_LABEL           1010

// Board Size controls
#define IDC_LEN_MAX_EDIT            1101
#define IDC_LEN_MAX_SPIN            1102
#define IDC_LEN_MIN_EDIT            1103
#define IDC_LEN_MIN_SPIN            1104
#define IDC_LEN_LOCK                1105
#define IDC_LEN_SPR_EDIT            1106
#define IDC_LEN_SPR_SPIN            1107

#define IDC_WID_MAX_EDIT            1111
#define IDC_WID_MAX_SPIN            1112
#define IDC_WID_MIN_EDIT            1113
#define IDC_WID_MIN_SPIN            1114
#define IDC_WID_LOCK                1115
#define IDC_WID_SPR_EDIT            1116
#define IDC_WID_SPR_SPIN            1117

#define IDC_GROUT_L_EDIT            1121
#define IDC_GROUT_L_SPIN            1122
#define IDC_GROUT_W_EDIT            1123
#define IDC_GROUT_W_SPIN            1124
#define IDC_GROUT_LOCK              1125

#define IDC_ROW_MIN_EDIT            1131
#define IDC_ROW_MIN_SPIN            1132
#define IDC_ROW_MAX_EDIT            1133
#define IDC_ROW_MAX_SPIN            1134
#define IDC_ROW_LOCK                1135

#define IDC_DO_EXTRUDE              1141
#define IDC_EXTRUDE_EDIT            1142
#define IDC_EXTRUDE_SPIN            1143
#define IDC_DO_BEVEL                1144
#define IDC_BEVEL_EDIT              1145
#define IDC_BEVEL_SPIN              1146
#define IDC_OUTLINE_EDIT            1147
#define IDC_OUTLINE_SPIN            1148
#define IDC_OUTLINE_LOCK            1149
#define IDC_DO_GROUT                1150
#define IDC_GROUT_DEPTH_EDIT        1151
#define IDC_GROUT_DEPTH_SPIN        1152
#define IDC_GROUT_MATID_EDIT        1153
#define IDC_GROUT_MATID_SPIN        1154

// Variation controls
#define IDC_ROT_MAX_EDIT            1201
#define IDC_ROT_MAX_SPIN            1202
#define IDC_ROT_MIN_EDIT            1203
#define IDC_ROT_MIN_SPIN            1204
#define IDC_ROT_SPR_EDIT            1205
#define IDC_ROT_SPR_SPIN            1206

#define IDC_OFFX_MAX_EDIT           1211
#define IDC_OFFX_MAX_SPIN           1212
#define IDC_OFFX_MIN_EDIT           1213
#define IDC_OFFX_MIN_SPIN           1214
#define IDC_OFFX_SPR_EDIT           1215
#define IDC_OFFX_SPR_SPIN           1216

#define IDC_OFFSET_LOCK             1220

#define IDC_OFFY_MAX_EDIT           1221
#define IDC_OFFY_MAX_SPIN           1222
#define IDC_OFFY_MIN_EDIT           1223
#define IDC_OFFY_MIN_SPIN           1224
#define IDC_OFFY_SPR_EDIT           1225
#define IDC_OFFY_SPR_SPIN           1226

#define IDC_TILT_MAX_EDIT           1231
#define IDC_TILT_MAX_SPIN           1232
#define IDC_TILT_MIN_EDIT           1233
#define IDC_TILT_MIN_SPIN           1234
#define IDC_TILT_SPR_EDIT           1235
#define IDC_TILT_SPR_SPIN           1236

#define IDC_OVERLAP_EDIT            1241
#define IDC_OVERLAP_SPIN            1242

// General controls
#define IDC_SCALE_EDIT              1301
#define IDC_SCALE_SPIN              1302
#define IDC_DIR_EDIT                1303
#define IDC_DIR_SPIN                1304
#define IDC_SEED_EDIT               1305
#define IDC_SEED_SPIN               1306
#define IDC_OBJOFFX_EDIT            1307
#define IDC_OBJOFFX_SPIN            1308
#define IDC_OBJOFFY_EDIT            1309
#define IDC_OBJOFFY_SPIN            1310
#define IDC_DO_WELD                 1311
#define IDC_WELD_EDIT               1312
#define IDC_WELD_SPIN               1313

// UV Settings controls
#define IDC_UV_CHAN_EDIT            1401
#define IDC_UV_CHAN_SPIN            1402
#define IDC_UV_FLIP_U               1403
#define IDC_UV_FLIP_V               1404
#define IDC_UV_RAND_U               1405
#define IDC_UV_RAND_V               1406

// Warnings controls
#define IDC_WARN_MAX_EDIT           1501
#define IDC_WARN_MAX_SPIN           1502

// Update controls
#define IDC_UPDATE_ALWAYS           1601
#define IDC_UPDATE_MANUAL           1602
#define IDC_UPDATE_BTN              1603

// Presets controls
#define IDC_PRESET_SAVE             1701
#define IDC_PRESET_LOAD             1702

// Credits controls
#define IDC_CREDITS_LINK            1801

// Border controls
#define IDC_DO_BORDER               1901
#define IDC_BORDER_WIDTH_EDIT       1902
#define IDC_BORDER_WIDTH_SPIN       1903
#define IDC_BORDER_OFFSET_EDIT      1904
#define IDC_BORDER_OFFSET_SPIN      1905
#define IDC_BORDER_CUT_COMBO        1906
#define IDC_BORDER_MATID_EDIT       1907
#define IDC_BORDER_MATID_SPIN       1908
#define IDC_BORDER_EDIT_LINES       1909
#define IDC_BORDER_OFF_BOT_EDIT     1910
#define IDC_BORDER_OFF_BOT_SPIN     1911
#define IDC_BORDER_OFF_TOP_EDIT     1912
#define IDC_BORDER_OFF_TOP_SPIN     1913
#define IDC_BORDER_OFF_LEFT_EDIT    1914
#define IDC_BORDER_OFF_LEFT_SPIN    1915
#define IDC_BORDER_OFF_RIGHT_EDIT   1916
#define IDC_BORDER_OFF_RIGHT_SPIN   1917
#define IDC_BORDER_RESET            1918
#define IDC_BORDER_PAT_COMBO        1919
#define IDC_BORDER_TILESIZE_EDIT    1920
#define IDC_BORDER_TILESIZE_SPIN    1921
