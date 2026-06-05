/*
 * File: _coder_ekf_soc_step_cg_api.h
 *
 * MATLAB Coder version            : 25.1
 * C/C++ source code generated on  : 2026-06-05 15:20:07
 */

#ifndef _CODER_EKF_SOC_STEP_CG_API_H
#define _CODER_EKF_SOC_STEP_CG_API_H

/* Include Files */
#include "emlrt.h"
#include "mex.h"
#include "tmwtypes.h"
#include <string.h>

/* Type Definitions */
#ifndef typedef_struct0_T
#define typedef_struct0_T
typedef struct {
  real_T R0_Ohm;
  real_T R1_Ohm;
  real_T C1_F;
  real_T Cap_Ah;
  real_T SOC_bp[21];
  real_T OCV_bp[21];
  real_T soc0;
  real_T Q[4];
  real_T R;
  real_T P0[4];
} struct0_T;
#endif /* typedef_struct0_T */

/* Variable Declarations */
extern emlrtCTX emlrtRootTLSGlobal;
extern emlrtContext emlrtContextGlobal;

#ifdef __cplusplus
extern "C" {
#endif

/* Function Declarations */
void ekf_soc_step_cg(real_T I_k, real_T V_k, real_T dt, struct0_T *prm,
                     boolean_T reset, real_T *soc, real_T *vrc, real_T *vhat);

void ekf_soc_step_cg_api(const mxArray *const prhs[5], int32_T nlhs,
                         const mxArray *plhs[3]);

void ekf_soc_step_cg_atexit(void);

void ekf_soc_step_cg_initialize(void);

void ekf_soc_step_cg_terminate(void);

void ekf_soc_step_cg_xil_shutdown(void);

void ekf_soc_step_cg_xil_terminate(void);

#ifdef __cplusplus
}
#endif

#endif
/*
 * File trailer for _coder_ekf_soc_step_cg_api.h
 *
 * [EOF]
 */
