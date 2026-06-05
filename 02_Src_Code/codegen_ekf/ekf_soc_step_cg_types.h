/*
 * File: ekf_soc_step_cg_types.h
 *
 * MATLAB Coder version            : 25.1
 * C/C++ source code generated on  : 2026-06-05 15:20:07
 */

#ifndef EKF_SOC_STEP_CG_TYPES_H
#define EKF_SOC_STEP_CG_TYPES_H

/* Include Files */
#include "rtwtypes.h"

/* Type Definitions */
#ifndef typedef_struct0_T
#define typedef_struct0_T
typedef struct {
  double R0_Ohm;
  double R1_Ohm;
  double C1_F;
  double Cap_Ah;
  double SOC_bp[21];
  double OCV_bp[21];
  double soc0;
  double Q[4];
  double R;
  double P0[4];
} struct0_T;
#endif /* typedef_struct0_T */

#endif
/*
 * File trailer for ekf_soc_step_cg_types.h
 *
 * [EOF]
 */
